---
name: monao-create
description: 墨脑创作闭环 Skill —— 通过墨脑 Open API 驱动「素材 → 选题 → 文章 → 审稿 → 改稿」全流程。当用户想查看/收录素材、用素材生成选题、查看或修改文章、审稿（通过或退回待修改并提修改要求）时使用。触发词：素材、收录、灵感、选题、生成文章、文章列表、审稿、审稿通过、待修改、改稿、修改文章。
---

# 墨脑创作（monao-create）

用墨脑 Open API 完成一篇文章的完整创作闭环：

```
素材(灵感) ──生成选题──▶ 选题卡 ──AI员工创作──▶ 文章 ──审稿──▶ 通过→待发布
   ▲                                                    │
   └──────────────── 待修改+修改要求 ◀──────改稿────────┘
```

## 配置

- **令牌**：环境变量 `MONAO_API_TOKEN`（`sk-xxx`）。在「开放平台 → 令牌管理」创建。`install.sh` 已写入 `workspace-monao/.env`，`monao.sh` 会自动读取。
- **基址**：`MONAO_BASE_URL`，默认 `https://brc.aismrti.com`。
- **认证头**：所有请求带 `X-Api-Token: $MONAO_API_TOKEN`。
- **返回约定**：`{ "code": 200, "data": ... }`，`code != 200` 即失败，`message` 为原因。
- 大多数接口在 `/open-api/*`；**素材与审稿在 `/api/*`，但同一个令牌即可访问**（后端对带令牌的 `/api/*` 一视同仁）。

> 封装脚本：`scripts/monao.sh`（薄封装，自动带令牌、格式化 JSON）。`bash scripts/monao.sh help` 看全部子命令。下文每个能力都给出 `monao.sh` 与等价 `curl` 两种写法。

## ⚠️ 两个 ID 别搞混

`GET /open-api/articles` 的每条文章同时有两个 ID：

| 字段 | 含义 | 用在哪 |
|------|------|--------|
| `id` | 系统文章 ID | **审稿**接口 `/api/reviews/{articleId}` |
| `bjArticleId` | 笔尖文章 ID | **文章详情/改稿**接口 `/open-api/articles/{bjArticleId}`、`/open-api/bj-article/*` |

先 `article-list` 拿到这两个 ID，再分别用于审稿和改稿。

---

## 1. 查询我的素材（默认未使用）

未使用 = 还没转成选题，即 `status` 不是 `CONVERTED`（已转选题）也不是 `ARCHIVED`（已归档）。其它状态：`PENDING`（待评估）、`EVALUATED`（已评估）。

```bash
# 默认只回未使用素材（已在客户端过滤 CONVERTED/ARCHIVED）
bash scripts/monao.sh material-list
bash scripts/monao.sh material-list --keyword "AI Agent" --page 1
bash scripts/monao.sh material-list --status EVALUATED   # 指定状态
bash scripts/monao.sh material-list --all                # 不过滤，看全部
bash scripts/monao.sh material-get 123                   # 详情
```

等价 curl：
```bash
curl -s -H "X-Api-Token: $MONAO_API_TOKEN" \
  "$MONAO_BASE_URL/api/inspiration?pageNum=1&pageSize=20&keyword=AI%20Agent"
```
响应 `data.records[]`：`{ id, title, content, status, score, sourceUrl, materialType, createdAt }`。

## 2. 新增 / 更新 / 收录素材

收录支持 4 种 `materialType`：`url`（粘链接，后端抓正文）、`text`（直接给正文）、`inspiration`（灵感笔记）、`article`（整篇文章）。

```bash
# 收录一个链接（content 可空，后端抓取）
bash scripts/monao.sh material-add --data '{"materialType":"url","sourceUrl":"https://example.com/post","tags":"AI,产品"}'

# 收录一段文本（text 模式 content 必填）
bash scripts/monao.sh material-add --data '{"materialType":"text","title":"标题","content":"正文……","tags":"随笔"}'

# 正文很长时写文件再传，避免转义
echo '{"materialType":"text","title":"长文","content":"……"}' > /tmp/m.json
bash scripts/monao.sh material-add --file /tmp/m.json

# 更新已有素材
bash scripts/monao.sh material-update 123 --data '{"title":"新标题","tags":"已整理","note":"备注"}'
```

等价 curl：`POST /api/inspiration`、`PUT /api/inspiration/{id}`，body 见上。可更新字段：`title / content / tags / note / folderId`。

## 3. 用素材生成选题（分配 AI 员工）→ 出文章

`POST /open-api/topic-cards`。**想要可靠出文章，用 `topic-generate`**（专家模式直存，建卡后直接派活生成）：

```bash
# 先取一个 employeeId（员工=AI员工，真实 ID 如 345，不是 1）
bash scripts/monao.sh get /open-api/employees    # data[].id

# ★推荐★ 建选题并保证派活生成
bash scripts/monao.sh topic-generate \
  --content "AI Agent 正在重塑 SaaS：从工具到员工" \
  --topic "AI Agent 把 SaaS 从工具变成员工" \
  --reference "素材链接/要点……" \
  --employee 345 \
  --require "面向产品经理，案例驱动，结尾给行动清单"
# → data.topicCardId（如 3587），status 立即为 ASSIGNED

# 轮询生文状态，直到 status=GENERATED 拿到 bjArticleId
bash scripts/monao.sh topic-status 3587
# data: { status, bjArticleId, articleId, ... } —— articleId=系统ID(审稿用), bjArticleId=笔尖ID(改稿用)
```

> ⚠️ **为什么不用默认的 `topic-create`？** `topic-create` 默认走 **AI 模式**（不带 `score`/`decision`）。
> 后端异步 worker 有硬门槛：**只有 AI 评审 `decision==accept` 才会派活生成**；而当员工绑定的是
> v2 一步式 XML 选题提示词时，`decision` 恒被置为 `revise`（产品设计：不评分、全部人工过审），
> 于是选题卡**永久停在 `CREATED`、`assignmentCount=0`、无任何报错**。`topic-generate` 传
> `score`+`decision=accept`+`needAiOptimize=false` 走专家模式，后端直接 `assign` 派活，绕过该门槛。
> 若你确实要原始透传，`topic-create` 的 body 里也必须同时带 `"score"` 和 `"decision":"accept"`（缺一即被卡）。

请求体字段（`topic-generate` 自动填好 `needAiOptimize/score/decision/autoAssign`，下表供 `topic-create` 透传参考）：

| 字段 | 必填 | 说明 |
|------|------|------|
| `contentText` | 是 | 选题主体/主题，或要写什么的简述（可直接放素材正文） |
| `topic` | 否 | 独立主题，优先作为选题标题 |
| `referenceMaterial` | 否 | 参考素材/证据清单（独立存储，不被 AI 覆盖） |
| `employeeId` | 否 | 指定 AI 员工（真实 ID 从 `GET /open-api/employees` 取，如 345；不传则系统默认分配） |
| `userRequire` | 否 | 用户要求（拼进三要素的观点要求） |
| `score` | **派活必填** | 选题评分 0-100；与 `decision` 同时缺失会被门槛卡住 |
| `decision` | **派活必填** | 必须 `accept` 才会派活生成；`revise`/`reject` 只建卡不生成 |
| `autoAssign` | 否 | 默认 `true`；`false` 只建卡不创作 |
| `needAiOptimize` | 否 | 默认 `true`；`false` + `score` + `decision` 走专家模式直存并派活 |

选题列表/详情：`topic-list`、`topic-get <id>`（`topic-get` 的 `assignmentCount=1` 即已派活）。

## 4. 查询文章列表 / 详情

```bash
bash scripts/monao.sh article-list                 # 最近文章（含 id 与 bjArticleId）
bash scripts/monao.sh article-list --status 0      # 按发布状态过滤
bash scripts/monao.sh article-get 2920019015239424 # 详情(用 bjArticleId，返回笔尖最新 HTML)
bash scripts/monao.sh to-publish                   # 已生成且审稿通过的待发布文章
```

`GET /open-api/articles` 的 `data.records[]`：`{ id, bjArticleId, title, content, digest, coverUrl, wordCount, publishStatus, bjReadUrl, readUrl }`。

## 5. 审稿：通过 / 待修改（articleId = 系统 id）

流程：触发 AI 审稿 → 读结果 → 下决策。

```bash
# 触发 AI 审稿（异步）
bash scripts/monao.sh review-run 456            # 456 = 文章列表里的 id
# 轮询读结果，status: 0审稿中 1完成 2失败
bash scripts/monao.sh review-get 456
# data: { status, overallScore, contentScore, structureScore, readabilityScore,
#         strengths, weaknesses, suggestions }

# ✅ 审稿通过 → 文章进入待发布
bash scripts/monao.sh review-approve 456 --score 88 --comment "结构清晰，可发"

# ✋ 待修改 → 记录修改要求（文章不进待发布；要求用于下一步改稿）
bash scripts/monao.sh review-revise 456 --requirements "开头太平，加一个反差钩子；第3段补一个数据案例"
```

决策接口：`POST /api/reviews/{articleId}/decision`，body `{ "decision":"approve"|"revise", "score"?, "comment"?, "requirements"? }`。
- `approve` 复用确认逻辑：收口待办 + 触发自动配图，文章出现在 `to-publish`。
- `revise` 把 `requirements` 写入审稿建议，**返回的对象里 `suggestions` 即修改要求**，直接喂给第 6 步改稿。

> ⚠️ **`review-run`（AI 审稿）当前返回 500，先别用**。直接走决策路：你（Agent）先用 `article-get` 通读全文，
> 自己判断后 `review-approve`（通过）或 `review-revise`（退修）——二者**不依赖 AI 审稿记录即可直接生效**（已实测）。

## 6. 修改文章（bjArticleId）

拿第 5 步的修改要求改稿。三种方式：

```bash
# 整篇改稿（最常用，把修改要求当指令）
bash scripts/monao.sh article-rewrite 2920019015239424 --instruction "开头加反差钩子；第3段补数据案例"

# 局部修改（精确改某段）
bash scripts/monao.sh article-partial-edit 2920019015239424 \
  --selected "原文里要改的那句" --instruction "改写得更口语"

# 直改正文/封面（自己拼好 HTML/封面图）
bash scripts/monao.sh article-set-content 2920019015239424 --data '{"content":"<p>新正文</p>"}'

# 历史版本 / 回滚
bash scripts/monao.sh article-versions 2920019015239424
bash scripts/monao.sh article-rollback 2920019015239424 --version 2
```

接口：`POST /open-api/bj-article/rewrite`、`/partial-edit`、`/rollback`（body 里 `articleId` 填 **bjArticleId**）；`PUT /open-api/articles/{bjArticleId}/content`（`content` / `coverUrl` 至少一项）。改完通常回到第 5 步重新 `review-approve`。

---

## 端到端示例（一句话需求 → 待发布）

```bash
# 0) 取一个真实 employeeId
bash scripts/monao.sh get /open-api/employees                 # → 如 345
# 1) 找一条未使用素材
bash scripts/monao.sh material-list
# 2) 用它建选题并「保证派活生成」（★用 topic-generate，不要用裸 topic-create）
bash scripts/monao.sh topic-generate --content "<素材主题>" --employee 345 \
  --reference "<要点>" --require "<创作要求>"                  # → topicCardId 3587（status=ASSIGNED）
# 3) 轮询直到 status=GENERATED，拿到 articleId(系统ID) 与 bjArticleId(笔尖ID)
bash scripts/monao.sh topic-status 3587
# 4) 文章已可读/可列：article-get <bjArticleId> 通读，article-list 也能看到
bash scripts/monao.sh article-get 3414555556383232
# 5) Agent 自己判断后下决策（不跑 review-run）：不满意 → 退修
bash scripts/monao.sh review-revise 2176 --requirements "……"    # 2176 = articleId(系统ID)
# 6) 按要求改稿（bjArticleId），再通过
bash scripts/monao.sh article-rewrite 3414555556383232 --instruction "……"
bash scripts/monao.sh review-approve 2176 --comment "已按意见修改"
# 7) 确认进入待发布
bash scripts/monao.sh to-publish
```

## 排错

- **选题卡卡在 `CREATED`、`assignmentCount=0`、无报错、永远不出文章**：最常见坑。原因是用了裸 `topic-create`（AI 模式）被
  `decision != accept` 门槛拦下（XML 提示词员工 `decision` 恒为 `revise`）。**改用 `topic-generate`**（或给 `topic-create` body
  补 `"score"`+`"decision":"accept"`）即走专家模式直接派活。判断信号：`topic-get <id>` 看 `assignmentCount`，=1 才是派活成功。
- `article-get <bjArticleId>` 报「文章不存在」(404)：①把系统 `articleId` 当成了 `bjArticleId`（审稿用 `articleId`，改稿/详情用 `bjArticleId`）；
  ②该 `bjArticleId` 对应的笔尖文章已被删除（老选题常见）。新生成的文章 `article-get`/`article-list` 正常可读。
- `review-run` 报 500：AI 审稿入口当前异常，**跳过它**，直接 `review-approve`/`review-revise` 下决策即可。
- `code: 401/403` 或「需要 VIP」：令牌无效/未开通 VIP。重新在「开放平台 → 令牌管理」确认令牌、确认账号为 VIP。
- 选题已派活但迟迟不出文章：`topic-status` 看 `status`/`errorMessage`；笔尖创作是异步的，正常数十秒到数分钟。
