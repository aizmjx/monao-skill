# monao-create-skill

墨脑创作闭环 Skill —— 通过墨脑 Open API（`https://brc.aismrti.com`）驱动「素材 → 选题 → 文章 → 审稿 → 改稿」全流程。

供 OpenClaw / QClaw agent 使用，由墨脑后端以 tar.gz 经 `install.sh` 分发，安装到 `~/.openclaw/workspace-monao/skills/monao-create/`。

```
monao-create-skill/
├── SKILL.md            # 主文件：6 大能力 → Open API 映射 + 端到端工作流
├── scripts/monao.sh    # 薄封装（自动带令牌、格式化 JSON）
└── package.sh          # 打 tar.gz 发布包
```

## 六大能力

1. 查询素材（默认未使用）—— `GET /api/inspiration`
2. 新增/更新/收录素材 —— `POST|PUT /api/inspiration`
3. 用素材生成选题、分配 AI 员工 —— `POST /open-api/topic-cards`
4. 审稿：通过 / 待修改+修改要求 —— `POST /api/reviews/{id}/decision`
5. 修改文章（整篇/局部/直改） —— `/open-api/bj-article/*`
6. 文章列表 / 详情 —— `GET /open-api/articles`

详见 [SKILL.md](./SKILL.md)。

## 本地使用

```bash
export MONAO_API_TOKEN=sk-xxx          # 墨脑「开放平台 → 令牌管理」获取
bash scripts/monao.sh help
bash scripts/monao.sh material-list
```

## 打包 & 发布（管理员）

```bash
# 1) 打包（产物 dist/monao-create-vX.Y.Z.tar.gz，只含 SKILL.md + scripts/）
./package.sh 1.0.0

# 2) 上传到墨脑后端（管理员令牌；同名 + 更高版本号 = 自动更新）
curl -H "X-Api-Token: $ADMIN_TOKEN" \
  -F file=@dist/monao-create-v1.0.0.tar.gz \
  -F name=monao-create -F version=1.0.0 \
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
