---
name: monao-create
description: 当用户想在墨脑（brc.aismrti.com）平台收录或查询素材、用素材生成选题并派给 AI 员工出文章、查看或修改文章、对文章审稿（通过或退回待修改并提修改要求）、按要求改稿、或查看待发布文章时使用。触发词：墨脑、素材、灵感、收录、选题、生成文章、文章列表、审稿、审稿通过、待修改、改稿、修改文章、待发布。
---

# 墨脑创作（monao-create）

用墨脑 Open API 跑通一篇文章的创作闭环：素材 → 选题 → 文章 → 审稿 → 改稿。

```
素材(灵感) ──生成选题──▶ 选题卡 ──AI员工创作──▶ 文章 ──审稿──▶ 通过→待发布
   ▲                                                    │
   └──────────────── 待修改+修改要求 ◀──────改稿────────┘
```

封装脚本 `scripts/monao.sh`（自动带令牌、格式化 JSON）。**全部子命令和 flag 看 `bash scripts/monao.sh help`**——本文不重复列 flag，只讲怎么用、坑在哪。

## ⚠️ 开工前必读：3 个会让你白忙的坑

1. **出文章必须用 `topic-generate`，别用裸 `topic-create`。**
   裸 `topic-create` 走 AI 模式，后端异步 worker 有硬门槛：只有 AI 评审 `decision==accept` 才派活生成；而员工绑的是 v2 一步式 XML 选题提示词时 `decision` 恒被置为 `revise`（产品设计：不评分、全人工过审），于是选题卡**永久卡在 `CREATED`、`assignmentCount=0`、毫无报错**。`topic-generate` 走专家模式（自动带 `score`+`decision=accept`+`needAiOptimize=false`）直接 `assign` 派活，绕过门槛。判断派活成功：`topic-get <id>` 看 `assignmentCount==1`。

2. **两个 ID 别搞混。** 每篇文章同时有两个 ID，用错就报 404：
   - `id`（系统文章 ID）→ **审稿决策**接口 `/api/reviews/{articleId}/decision`
   - `bjArticleId`（笔尖文章 ID）→ **文章详情 / 改稿**接口 `/open-api/articles/{bjArticleId}`、`/open-api/bj-article/*`
   先 `article-list` 或 `topic-status` 拿到两个，再分别用。

3. **`review-run`（AI 审稿）当前返回 500，跳过它。** 直接走决策路：你（Agent）先用 `article-get` 通读全文，自己判断后 `review-approve`（通过）或 `review-revise`（退修）——二者不依赖 AI 审稿记录即可直接生效（已实测）。

## 配置

- **令牌**：环境变量 `MONAO_API_TOKEN`（`sk-xxx`，在「开放平台 → 令牌管理」创建；`install.sh` 已写入 `workspace-monao/.env`，`monao.sh` 自动读取）。
- **基址**：`MONAO_BASE_URL`，默认 `https://brc.aismrti.com`。
- **认证**：所有请求带头 `X-Api-Token: $MONAO_API_TOKEN`（裸 curl 示例：`curl -s -H "X-Api-Token: $MONAO_API_TOKEN" "$MONAO_BASE_URL/api/inspiration?pageNum=1&pageSize=20"`）。
- **返回约定**：`{ "code": 200, "data": ... }`，`code != 200` 即失败，`message` 为原因。
- **接口前缀**：多数在 `/open-api/*`；素材与审稿在 `/api/*`——同一令牌都能访问（后端对带令牌的 `/api/*` 一视同仁）。
- **员工(AI员工)真实 `employeeId`** 从 `monao.sh get /open-api/employees` 取（`data[].id`，如 345，不是 1）。

## 能力 → 接口速查

| 能力 | 命令（`monao.sh`） | 接口 |
|------|------|------|
| 查素材（默认未使用） | `material-list [--all/--status S/--keyword K]`、`material-get <id>` | `GET /api/inspiration` |
| 收录 / 更新素材 | `material-add --data J\|--file F`、`material-update <id> --data J` | `POST`/`PUT /api/inspiration` |
| ★生成选题并派活★ | `topic-generate --content ... [--topic --reference --employee --require]` | `POST /open-api/topic-cards` |
| 选题列表 / 详情 / 生文状态 | `topic-list`、`topic-get <id>`、`topic-status <id>` | `GET /open-api/topic-cards*` |
| 文章列表 / 详情 / 待发布 | `article-list`、`article-get <bjArticleId>`、`to-publish` | `GET /open-api/articles` |
| 审稿决策 | `review-approve <articleId>`、`review-revise <articleId> --requirements ...` | `POST /api/reviews/{articleId}/decision` |
| 改稿 | `article-rewrite <bjArticleId> --instruction ...`（及 partial-edit/set-content/versions/rollback） | `POST /open-api/bj-article/*` |

## 关键细节

**素材状态**：未使用 = 非 `CONVERTED`（已转选题）且非 `ARCHIVED`（已归档）；其它 `PENDING`（待评估）/`EVALUATED`（已评估）。`material-list` 默认已过滤为未使用，`--all` 看全部。响应 `data.records[]`：`{ id, title, content, status, score, sourceUrl, materialType, createdAt }`。

**收录 `materialType`**：`url`（粘链接，后端抓正文，content 可空）/ `text`（直接给正文，content 必填）/ `inspiration`（灵感笔记）/ `article`（整篇）。正文很长时写文件再 `--file /tmp/m.json`，避免转义。可更新字段：`title / content / tags / note / folderId`。

**生成选题字段**（`topic-generate` 已自动填好派活四件套；下表供 `topic-create` 原始透传参考）：

| 字段 | 必填 | 说明 |
|------|------|------|
| `contentText` | 是 | 选题主体/主题，或要写什么的简述（可直接放素材正文） |
| `topic` | 否 | 独立主题，优先作选题标题 |
| `referenceMaterial` | 否 | 参考素材/证据清单（独立存储，不被 AI 覆盖） |
| `employeeId` | 否 | 指定 AI 员工；不传则系统默认分配 |
| `userRequire` | 否 | 用户要求（拼进三要素的观点要求） |
| `score` + `decision=accept` | **派活必填** | 缺一即被门槛卡住，只建卡不生成（见必读坑①） |
| `needAiOptimize=false` | — | 配合上面走专家模式直存并派活 |

`topic-status <id>` 轮询到 `status=GENERATED` 拿结果，`data`：`{ status, articleId(系统ID,审稿用), bjArticleId(笔尖ID,改稿/详情用), errorMessage, ... }`。

**文章** `article-list` / `article-get <bjArticleId>`，`data.records[]`：`{ id, bjArticleId, title, content, digest, coverUrl, wordCount, publishStatus, bjReadUrl, readUrl }`。

**审稿决策**：`POST /api/reviews/{articleId}/decision`，body `{ decision:"approve"|"revise", score?, comment?, requirements? }`。
- `approve` → 收口待办 + 触发自动配图，文章进 `to-publish`。
- `revise` → `requirements` 写入审稿建议；**返回对象里 `suggestions` 即修改要求**，直接喂给改稿。

**改稿**（接口 body 里 `articleId` 填 **bjArticleId**）：`article-rewrite`（整篇，把修改要求当指令）/ `article-partial-edit --selected "原文" --instruction ...`（局部）/ `article-set-content --data '{"content":"<p>…</p>"}'`（直改 HTML/封面）/ `article-versions` + `article-rollback --version N`（版本/回滚）。改完通常回到审稿重新 `review-approve`。

## 端到端示例（一句话需求 → 待发布）

```bash
# 0) 取真实 employeeId
bash scripts/monao.sh get /open-api/employees                  # → 如 345
# 1) 找一条未使用素材
bash scripts/monao.sh material-list
# 2) ★ 用 topic-generate（不要裸 topic-create），保证派活生成
bash scripts/monao.sh topic-generate --content "<素材主题>" --employee 345 \
  --reference "<要点>" --require "<创作要求>"                   # → topicCardId（status=ASSIGNED）
# 3) 轮询到 GENERATED，拿 articleId(系统ID) 与 bjArticleId(笔尖ID)
bash scripts/monao.sh topic-status <topicCardId>
# 4) 通读全文（不跑 review-run）
bash scripts/monao.sh article-get <bjArticleId>
# 5) Agent 自己判断后下决策：不满意 → 退修（用 articleId）
bash scripts/monao.sh review-revise <articleId> --requirements "<意见>"
# 6) 按要求改稿（用 bjArticleId），再通过
bash scripts/monao.sh article-rewrite <bjArticleId> --instruction "<按意见改>"
bash scripts/monao.sh review-approve <articleId> --comment "已按意见修改"
# 7) 确认进入待发布
bash scripts/monao.sh to-publish
```

## 排错

| 症状 | 原因 / 解法 |
|------|------|
| 选题卡卡在 `CREATED`、`assignmentCount=0`、无报错、不出文章 | **最常见坑（必读①）**。用了裸 `topic-create` 被 `decision!=accept` 门槛拦下。改用 `topic-generate`（或给 body 补 `score`+`"decision":"accept"`）。`topic-get <id>` 看 `assignmentCount==1` 才算派活成功。 |
| `article-get <bjArticleId>` 报「文章不存在」(404) | ①把系统 `articleId` 当成了 `bjArticleId`（审稿用 articleId、改稿/详情用 bjArticleId，必读②）；②该 bjArticleId 对应的笔尖文章已被删（老选题常见）。新生成的文章正常可读。 |
| `review-run` 报 500 | AI 审稿入口当前异常，**跳过**，直接 `review-approve`/`review-revise` 下决策即可（必读③）。 |
| `code: 401/403` 或「需要 VIP」 | 令牌无效 / 未开通 VIP。重新在「开放平台 → 令牌管理」确认令牌、确认账号为 VIP。 |
| 已派活但迟迟不出文章 | `topic-status` 看 `status`/`errorMessage`；笔尖创作异步，正常数十秒到数分钟。 |
