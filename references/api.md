# 墨脑创作 Open API 完整参考

配合 [../SKILL.md](../SKILL.md) 使用。认证、基址、返回约定见 SKILL.md「配置」节：
所有请求带头 `X-Api-Token: $MONAO_API_TOKEN`，写接口加 `Content-Type: application/json`，
返回统一 `{ code, message, data }`，`code != 200` 即失败（`message` 为原因）。

## 目录
- [素材（灵感池）](#素材灵感池-api)
- [选题](#选题-open-apitopic-cards)
- [文章](#文章-open-apiarticles)
- [审稿](#审稿-apireviews用系统-articleid)
- [改稿](#改稿-open-apibj-articlebody-里-articleid-填-bjarticleid)
- [AI 员工](#ai-员工)
- [排错速查](#排错速查)

---

## 素材（灵感池）/api/*

### 查询素材 · GET /api/inspiration
Query：`pageNum`(默认 1)、`pageSize`(默认 20)、`keyword`(可选)、`status`(可选)。
返回 `data.records[]`：`{ id, title, content, status, score, sourceUrl, materialType, createdAt, ... }`。
**「未使用」** = status 既非 `CONVERTED`（已转选题）也非 `ARCHIVED`（已归档）；其它状态 `PENDING`（待评估）/ `EVALUATED`（已评估）。
接口本身不自带「只看未使用」过滤——拉回后自己按 status 排除 `CONVERTED`/`ARCHIVED` 即可。

### 素材详情 · GET /api/inspiration/{id}

### 收录素材 · POST /api/inspiration
| 字段 | 说明 |
|------|------|
| `materialType` | `url`（粘链接，后端抓正文，content 可空）/ `text`（直接给正文，content 必填）/ `inspiration`（灵感笔记）/ `article`（整篇）|
| `title` | 标题 |
| `content` | 正文（text/article 必填；url 可空）|
| `sourceUrl` | 原文链接（url 类型用）|
| `tags` / `note` / `folderId` | 可选 |
正文很长时把 JSON 写文件再 `--data @/tmp/m.json`，避免转义。

### 更新素材 · PUT /api/inspiration/{id}
可更新 `title / content / tags / note / folderId`。

---

## 选题 · /open-api/topic-cards

### 建选题 · POST /open-api/topic-cards
**两种模式**：
- **专家模式（推荐，保证派活生成）**：带 `needAiOptimize:false` + `score` + `decision:"accept"`，命中「直存并派活」通道。详见 SKILL.md 坑①。
- 裸 AI 模式：不带 score/decision，进异步评审队列；XML 提示词员工评审恒 `revise` → 选题卡卡在 `CREATED`、不生成、无报错。**不要用它出文章。**

| 字段 | 必填 | 说明 |
|------|------|------|
| `contentText` | 是 | 选题主体/主题，或要写什么的简述（可直接放素材正文）|
| `needAiOptimize` | 派活必填 | 专家模式置 `false` |
| `score` | 派活必填 | 评分（如 80）；缺则被门槛卡住，只建卡不生成 |
| `decision` | 派活必填 | `"accept"`；缺则被门槛卡住 |
| `autoAssign` | 建议 | `true`，建卡后直接派活 |
| `topic` | 否 | 独立主题，优先作选题标题 |
| `referenceMaterial` | 否 | 参考素材/证据清单（独立存储，不被 AI 覆盖）|
| `userRequire` | 否 | 用户要求（拼进观点要求）|
| `employeeId` | 否 | 指定 AI 员工（真实 id 见 `/open-api/employees`）；不传则系统默认分配 |
返回 `data` = topicCardId。建后用 generation-status 轮询。

### 选题列表 · GET /open-api/topic-cards?pageNum=&pageSize=&status=

### 选题详情 · GET /open-api/topic-cards/{id}
看 `assignmentCount == 1` 判断派活成功（坑①）。

### 生文状态 · GET /open-api/topic-cards/{id}/generation-status
轮询到 `status=GENERATED`。`data`：`{ status, articleId(系统ID,审稿用), bjArticleId(笔尖ID,改稿/详情用), errorMessage, ... }`。
笔尖创作是异步的，正常数十秒到数分钟。

---

## 文章 · /open-api/articles

### 文章列表 · GET /open-api/articles?pageNum=&pageSize=&publishStatus=
`data.records[]`：`{ id, bjArticleId, title, content, digest, coverUrl, wordCount, publishStatus, bjReadUrl, readUrl }`。

### 文章详情 · GET /open-api/articles/{bjArticleId}
返回笔尖最新 HTML 正文。路径用 **bjArticleId**，不是系统 id（坑②）。
报「文章不存在」(404) 多半是：① 把系统 articleId 当成了 bjArticleId；② 该 bjArticleId 对应的笔尖文章已被删（老选题常见，新生成的文章正常可读）。

### 待发布 · GET /open-api/articles/to-publish
已生成且审稿通过的文章。

---

## 审稿 · /api/reviews（用系统 articleId）

### AI 审稿 · POST /api/reviews/start/{articleId}
**当前恒返回 500，跳过**（坑③）。改由 Agent 自己通读后走决策路。

### 读审稿 · GET /api/reviews/{articleId}

### 决策 · POST /api/reviews/{articleId}/decision
- 通过：`{"decision":"approve","score":<可选>,"comment":"<可选>"}` → 收口待办 + 触发自动配图，文章进 to-publish。
- 退修：`{"decision":"revise","requirements":"<修改要求>"}` → requirements 写入审稿建议；返回对象里的修改要求可直接喂给改稿。

---

## 改稿 · /open-api/bj-article/*（body 里 `articleId` 填 bjArticleId！坑②）

### 整篇改稿 · POST /open-api/bj-article/rewrite
`{"articleId":<bjArticleId>,"instruction":"<把修改要求当指令>"}`

### 局部修改 · POST /open-api/bj-article/partial-edit
`{"articleId":<bjArticleId>,"selectedText":"<原文片段>","instruction":"<怎么改>"}`

### 直改正文/封面 · PUT /open-api/articles/{bjArticleId}/content
Body 如 `{"content":"<HTML>"}`（路径用 bjArticleId）。

### 历史版本 · GET /open-api/bj-article/{bjArticleId}/versions

### 回滚 · POST /open-api/bj-article/rollback
`{"articleId":<bjArticleId>,"versionNumber":<N>}`
改完通常回到审稿重新 `approve`。

---

## AI 员工

### 员工列表 · GET /open-api/employees
`data[].id` 是真实 employeeId（如 345，不是 1）。建选题指定 `employeeId` 时用它。

---

## 排错速查

| 症状 | 原因 / 解法 |
|------|------|
| 选题卡卡在 `CREATED`、`assignmentCount=0`、无报错、不出文章 | 用了裸提交，被 `decision != accept` 门槛拦下。改专家模式（`needAiOptimize:false` + `score` + `decision:"accept"`）。坑① |
| 文章详情报「文章不存在」(404) | ① 把系统 `articleId` 当成了 `bjArticleId`（坑②）；② 该 bjArticleId 对应笔尖文章已删，新文章正常可读 |
| `review-run` 报 500 | AI 审稿入口当前异常，跳过，直接 `approve`/`revise` 决策。坑③ |
| `code` 401/403 或「需要 VIP」 | 令牌无效 / 未开通 VIP。在「开放平台 → 令牌管理」确认令牌、确认账号为 VIP |
| 已派活但迟迟不出文章 | `generation-status` 看 `status`/`errorMessage`；笔尖异步，数十秒到数分钟正常 |
