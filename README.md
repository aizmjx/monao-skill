# monao-create-skill

墨脑创作闭环 Skill —— 通过墨脑 Open API（`https://brc.aismrti.com`）驱动「素材 → 选题 → 文章 → 审稿 → 改稿」全流程。

纯标准 skill 格式：`SKILL.md` + `references/`，直接用 HTTP（curl）调接口，**不依赖任何脚本**。
供 OpenClaw / QClaw agent 使用，由墨脑后端以 tar.gz 经 `install.sh` 分发，安装到 `~/.openclaw/workspace-monao/skills/monao-create/`。

```
monao-create-skill/
├── SKILL.md            # 主文件：配置 + 三个坑 + 能力速查 + 端到端工作流
└── references/
    └── api.md          # 完整 Open API 参考（请求体 / 返回 / 排错）
```

## 六大能力

1. 查询素材（默认未使用）—— `GET /api/inspiration`
2. 收录 / 更新素材 —— `POST | PUT /api/inspiration`
3. 用素材生成选题、派给 AI 员工 —— `POST /open-api/topic-cards`（专家模式）
4. 审稿：通过 / 待修改+修改要求 —— `POST /api/reviews/{id}/decision`
5. 改稿（整篇/局部/直改/回滚）—— `/open-api/bj-article/*`
6. 文章列表 / 详情 / 待发布 —— `GET /open-api/articles`

详见 [SKILL.md](./SKILL.md) 与 [references/api.md](./references/api.md)。

## 配置

```bash
export MONAO_API_TOKEN=sk-xxx          # 墨脑「开放平台 → 令牌管理」获取
# 之后按 SKILL.md 直接 curl 调接口，例如：
curl -s -H "X-Api-Token: $MONAO_API_TOKEN" \
  "https://brc.aismrti.com/api/inspiration?pageNum=1&pageSize=20"
```

## 打包 & 发布（管理员）

```bash
# 1) 打包（产物只含 SKILL.md + references/，无脚本）
tar -czf dist/monao-create-vX.Y.Z.tar.gz SKILL.md references

# 2) 上传到墨脑后端（管理员令牌；同名 + 更高版本号 = 自动更新）
curl -H "X-Api-Token: $ADMIN_TOKEN" \
  -F file=@dist/monao-create-vX.Y.Z.tar.gz \
  -F name=monao-create -F version=X.Y.Z \
  -F displayName="墨脑创作" -F category=create \
  https://brc.aismrti.com/api/skills
```

上传后用户即可一键安装：

```bash
curl -fsSL https://brc.aismrti.com/open-api/install.sh | bash -s -- <token> --skill monao-create
```

## 相关

- 后端 / 前端（开放平台页、Open API）：`aizmjx/brc`
- 其它产品 skill：`aizmjx/monao-skill`（monorepo）、`aizmjx/tutu-skill`
