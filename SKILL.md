---
name: monao-create
description: 墨脑（brc.aismrti.com）内容创作闭环。当用户想收录或查询素材、用素材生成选题并派给 AI 员工出文章、查看或修改文章、对文章审稿（通过或退回待修改并提修改要求）、按要求改稿、或查看待发布文章时使用。触发词：墨脑、素材、灵感、收录、选题、生成文章、文章列表、审稿、审稿通过、待修改、改稿、修改文章、待发布。只要用户提到「墨脑」，或正在做「素材 → 选题 → 文章 → 审稿 → 改稿」链条里的任何一步，即使没有明确点名本工具，也应使用本 skill。
---

# 墨脑创作（monao-create）

直接用 HTTP 调墨脑 Open API，跑通一篇文章的创作闭环：

```
素材(灵感) ──生成选题──▶ 选题卡 ──AI员工创作──▶ 文章 ──审稿──▶ 通过→待发布
   ▲                                                    │
   └──────────────── 待修改+修改要求 ◀──────改稿────────┘
```

所有调用都是普通 HTTP 请求（用 `curl` 即可），认证只靠一个请求头。完整接口清单、请求体字段、返回结构与排错见 [references/api.md](references/api.md)；本文只讲怎么用、坑在哪。

## 配置

- **令牌**：环境变量 `MONAO_API_TOKEN`（形如 `sk-xxx`，在墨脑「开放平台 → 令牌管理」创建）。若环境变量没有，依次从 `~/.openclaw/workspace-monao/.env`、`~/.qclaw/workspace-monao/.env` 里读取 `MONAO_API_TOKEN=` 那一行。
- **基址**：`MONAO_BASE_URL`，默认 `https://brc.aismrti.com`。
- **认证**：每个请求都带头 `X-Api-Token: <令牌>`；写接口再加 `Content-Type: application/json`。
- **返回约定**：`{ "code": 200, "data": ... }`。`code != 200` 即失败，`message` 是原因。
- **接口前缀**：素材、审稿在 `/api/*`；选题、文章、改稿在 `/open-api/*`——同一个令牌都能访问。

读请求范式：

```bash
curl -s -H "X-Api-Token: $MONAO_API_TOKEN" \
  "$MONAO_BASE_URL/api/inspiration?pageNum=1&pageSize=20"
```

写请求范式：

```bash
curl -s -X POST -H "X-Api-Token: $MONAO_API_TOKEN" -H "Content-Type: application/json" \
  -d '{"contentText":"...","needAiOptimize":false,"autoAssign":true,"score":80,"decision":"accept"}' \
  "$MONAO_BASE_URL/open-api/topic-cards"
```

正文里有中文、换行或引号时，把 JSON 写进临时文件再用 `--data @/tmp/body.json`，省去转义麻烦。

## ⚠️ 开工前必读：三个会让你白忙的坑

这三条都来自真实踩坑——看似在跑、其实悄无声息地不出结果。先懂原理再动手：

**① 要出文章，选题必须走「专家模式直存派活」，不能裸提交。**
建选题用 `POST /open-api/topic-cards`，body 必须带 `needAiOptimize: false` + `score`（如 80）+ `decision: "accept"`，并建议带 `autoAssign: true`。
为什么：不带 score/decision 的「AI 模式」提交会进后端异步评审队列；而绑定 XML 选题提示词的 AI 员工，评审结论恒为 `revise`，后端只在 `decision == accept` 时才派活生成——于是选题卡**永久停在 `CREATED`、`assignmentCount=0`，且没有任何报错**，你会以为在生成、其实根本没动。专家模式带上 `score + decision:accept` 直接命中「直存并派活」通道，绕过这道门槛。
判断派活成功：`GET /open-api/topic-cards/{id}` 看 `assignmentCount == 1`。

**② 一篇文章有两个 ID，用错就 404。**
- **系统 `articleId`** → 走**审稿**：`/api/reviews/{articleId}/decision`
- **`bjArticleId`（笔尖文章 ID）** → 走**文章详情 / 改稿**：`/open-api/articles/{bjArticleId}`、`/open-api/bj-article/*`
- 尤其坑：改稿接口的 body 字段名叫 `articleId`，但要填的值是 **bjArticleId**，不是系统 id。
先用 `GET /open-api/topic-cards/{id}/generation-status` 或 `GET /open-api/articles` 把两个 ID 都拿到，再分别用。

**③ `review-run`（AI 审稿）当前恒返回 500，跳过它。**
直接走决策路：你（Agent）先 `GET /open-api/articles/{bjArticleId}` 通读全文，自己判断后调 `POST /api/reviews/{articleId}/decision` —— `approve`（通过）或 `revise`（退修）。决策路不依赖 AI 审稿记录，可直接生效。

## 能力 → 接口速查

| 能力 | 方法 路径 |
|------|------|
| 查素材（默认只看未使用）| `GET /api/inspiration?pageNum=&pageSize=&keyword=&status=` |
| 素材详情 | `GET /api/inspiration/{id}` |
| 收录 / 更新素材 | `POST /api/inspiration`、`PUT /api/inspiration/{id}` |
| ★建选题并派活★ | `POST /open-api/topic-cards`（专家模式 body，见坑①）|
| 选题列表 / 详情 / 生文状态 | `GET /open-api/topic-cards`、`/{id}`、`/{id}/generation-status` |
| 文章列表 / 详情 / 待发布 | `GET /open-api/articles`、`/{bjArticleId}`、`/to-publish` |
| 审稿通过 / 退修 | `POST /api/reviews/{articleId}/decision` |
| 改稿（整篇/局部/直改/版本/回滚）| `/open-api/bj-article/*`、`PUT /open-api/articles/{bjArticleId}/content` |
| AI 员工列表（取真实 employeeId）| `GET /open-api/employees`（`data[].id`，如 345）|

每个接口的请求体字段、返回结构、状态枚举与排错都在 [references/api.md](references/api.md)。

## 端到端：一句话需求 → 待发布

```bash
BASE="${MONAO_BASE_URL:-https://brc.aismrti.com}"
H=(-H "X-Api-Token: $MONAO_API_TOKEN")          # 认证头
J=(-H "Content-Type: application/json")         # 写接口加这个

# 0) 取真实 employeeId（可选，不传则系统默认分配）
curl -s "${H[@]}" "$BASE/open-api/employees"

# 1) 找一条未使用素材
curl -s "${H[@]}" "$BASE/api/inspiration?pageNum=1&pageSize=20"

# 2) ★专家模式★建选题并派活（保证生成，见坑①）
curl -s -X POST "${H[@]}" "${J[@]}" "$BASE/open-api/topic-cards" -d '{
  "contentText": "<素材主题或正文>",
  "needAiOptimize": false, "autoAssign": true,
  "score": 80, "decision": "accept",
  "referenceMaterial": "<要点/数据>", "userRequire": "<创作要求>",
  "employeeId": 345
}'                                               # → data 即 topicCardId

# 3) 轮询到 status=GENERATED，拿 articleId(系统) 与 bjArticleId(笔尖)
curl -s "${H[@]}" "$BASE/open-api/topic-cards/<topicCardId>/generation-status"

# 4) 通读全文（不跑 review-run）
curl -s "${H[@]}" "$BASE/open-api/articles/<bjArticleId>"

# 5) 自己判断后下决策：退修（用 articleId）
curl -s -X POST "${H[@]}" "${J[@]}" "$BASE/api/reviews/<articleId>/decision" \
  -d '{"decision":"revise","requirements":"<修改意见>"}'

# 6) 按意见改稿（用 bjArticleId），再通过
curl -s -X POST "${H[@]}" "${J[@]}" "$BASE/open-api/bj-article/rewrite" \
  -d '{"articleId":<bjArticleId>,"instruction":"<按意见改>"}'
curl -s -X POST "${H[@]}" "${J[@]}" "$BASE/api/reviews/<articleId>/decision" \
  -d '{"decision":"approve","comment":"已按意见修改"}'

# 7) 确认进入待发布
curl -s "${H[@]}" "$BASE/open-api/articles/to-publish"
```
