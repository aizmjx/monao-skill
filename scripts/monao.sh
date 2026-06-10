#!/usr/bin/env bash
#
# monao.sh — 墨脑（OpenClaw / QClaw）创作 Open API 封装
# 覆盖：素材(灵感) / 选题 / 文章 / 审稿 / 改稿 全闭环
#
# 配置（环境变量）：
#   MONAO_API_TOKEN   必填，开放平台 → 令牌管理 获取（sk-xxx）
#   MONAO_BASE_URL    可选，默认 https://brc.aismrti.com
#
# 用法：
#   bash monao.sh <command> [args]
#   bash monao.sh help
#
# 设计：薄封装。读接口给便捷子命令；写接口走 post/put 透传，请求体从
#       --data '<json>' / --file <path> / stdin 读取，避免 shell 转义踩坑。
#
set -euo pipefail

MONAO_BASE_URL="${MONAO_BASE_URL:-https://brc.aismrti.com}"

# ─────────────────────────── token ───────────────────────────
_load_token() {
  if [ -n "${MONAO_API_TOKEN:-}" ]; then return; fi
  local self_dir envf v
  self_dir="$(cd "$(dirname "$0")" && pwd)"
  for envf in "./.env" "${self_dir}/../.env" "${self_dir}/../../.env" \
              "${HOME}/.openclaw/workspace-monao/.env" "${HOME}/.qclaw/workspace-monao/.env"; do
    if [ -f "$envf" ]; then
      v="$(sed -n 's/^MONAO_API_TOKEN=//p' "$envf" 2>/dev/null | head -1)"
      [ -n "$v" ] && export MONAO_API_TOKEN="$v" && return
    fi
  done
  echo "❌ 未配置 MONAO_API_TOKEN（开放平台 → 令牌管理 获取 sk-xxx）" >&2
  exit 1
}

# ───────────────────── 通用请求（X-Api-Token） ─────────────────────
# _req METHOD PATH [BODY_JSON]
_req() {
  _load_token
  local method="$1" path="$2" body="${3:-}"
  local url="${MONAO_BASE_URL}${path}"
  local resp http
  if [ -n "$body" ]; then
    resp="$(curl -s -w $'\n%{http_code}' -X "$method" \
      -H "X-Api-Token: ${MONAO_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "$body" "$url")"
  else
    resp="$(curl -s -w $'\n%{http_code}' -X "$method" \
      -H "X-Api-Token: ${MONAO_API_TOKEN}" "$url")"
  fi
  http="$(printf '%s' "$resp" | tail -n1)"
  local payload; payload="$(printf '%s' "$resp" | sed '$d')"
  # 漂亮打印（有 python3 就格式化，否则原样）
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$payload" | python3 -c 'import sys,json;
d=sys.stdin.read()
try: print(json.dumps(json.loads(d),ensure_ascii=False,indent=2))
except Exception: sys.stdout.write(d)' 2>/dev/null || printf '%s\n' "$payload"
  else
    printf '%s\n' "$payload"
  fi
  if [ "$http" != "200" ]; then
    echo "⚠️  HTTP ${http}（业务 code 见上方 JSON）" >&2
  fi
}

# 从 --data/--file/stdin 解析请求体
_read_body() {
  local data="" file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --data) data="$2"; shift 2;;
      --file) file="$2"; shift 2;;
      *) shift;;
    esac
  done
  if [ -n "$data" ]; then printf '%s' "$data";
  elif [ -n "$file" ]; then cat "$file";
  elif [ ! -t 0 ]; then cat;
  else echo "{}"; fi
}

# urlencode（query 用）
_enc() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$1" 2>/dev/null || printf '%s' "$1"; }

usage() {
  cat <<'EOF'
墨脑创作 Open API — monao.sh

通用透传：
  get  <path>                         GET  请求
  post <path> [--data J|--file F]      POST 请求（无 --data 时读 stdin）
  put  <path> [--data J|--file F]      PUT  请求

素材（灵感池）：
  material-list [--unused|--status S] [--keyword K] [--page N] [--size N]
                                       查询素材，默认只看未使用（排除已转选题/已归档）
  material-get <id>                    素材详情
  material-add  [--data J|--file F]    收录/新增素材  POST /api/inspiration
  material-update <id> [--data J|...]  更新素材        PUT  /api/inspiration/{id}

选题：
  topic-create [--data J|--file F]     从素材生成选题  POST /open-api/topic-cards
  topic-list [--status S] [--page N]   选题列表
  topic-get <id>                       选题详情
  topic-status <id>                    选题生文状态（轮询用）

文章：
  article-list [--status N] [--page N] 文章列表（含 id 与 bjArticleId）
  article-get <bjArticleId>            文章详情（笔尖最新 HTML）
  to-publish                           待发布文章（已生成且审稿通过）

审稿（articleId = 文章列表里的系统 id）：
  review-run <articleId>               触发 AI 审稿
  review-get <articleId>               读审稿结果
  review-approve <articleId> [--score N --comment '...']   审稿通过 → 进待发布
  review-revise  <articleId> --requirements '...'          待修改 + 修改要求

改稿（bjArticleId = 文章列表里的 bjArticleId）：
  article-rewrite     <bjArticleId> --instruction '...'                整篇改稿
  article-partial-edit<bjArticleId> --selected '...' --instruction '...' 局部修改
  article-set-content <bjArticleId> [--data J|--file F]                直改正文/封面
  article-versions    <bjArticleId>                                   历史版本
  article-rollback    <bjArticleId> --version N                       回滚

环境：MONAO_API_TOKEN（必填）, MONAO_BASE_URL（默认 https://brc.aismrti.com）
EOF
}

# ─────────────────────────── 取参小工具 ───────────────────────────
_opt() { # _opt --flag "$@" -> 打印该 flag 的值
  local want="$1"; shift
  while [ $# -gt 0 ]; do
    if [ "$1" = "$want" ]; then printf '%s' "${2:-}"; return; fi
    shift
  done
}
_jstr() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1],ensure_ascii=False))' "$1" 2>/dev/null || printf '"%s"' "$1"; }

cmd="${1:-help}"; shift || true
case "$cmd" in
  help|-h|--help) usage ;;

  get)  _req GET "$1" ;;
  post) p="$1"; shift; _req POST "$p" "$(_read_body "$@")" ;;
  put)  p="$1"; shift; _req PUT  "$p" "$(_read_body "$@")" ;;

  # ── 素材 ──
  material-list)
    status="$(_opt --status "$@")"; kw="$(_opt --keyword "$@")"
    page="$(_opt --page "$@")"; size="$(_opt --size "$@")"
    q="pageNum=${page:-1}&pageSize=${size:-20}"
    [ -n "$kw" ] && q="${q}&keyword=$(_enc "$kw")"
    # 默认未使用：无显式 status 且未传 --all → 过滤 CONVERTED/ARCHIVED（客户端）
    if [ -n "$status" ]; then q="${q}&status=$(_enc "$status")"; fi
    out="$(_req GET "/api/inspiration?${q}")"
    if [ -z "$status" ] && ! printf '%s ' "$@" | grep -q -- '--all'; then
      echo "$out" | python3 -c '
import sys,json
try: d=json.loads(sys.stdin.read())
except Exception: print("(无法解析，原样见上)"); sys.exit()
rec=(d.get("data") or {}).get("records") or []
keep=[r for r in rec if r.get("status") not in ("CONVERTED","ARCHIVED")]
print(json.dumps({"unusedCount":len(keep),"records":keep},ensure_ascii=False,indent=2))' 2>/dev/null || echo "$out"
    else
      echo "$out"
    fi ;;
  material-get)    _req GET "/api/inspiration/$1" ;;
  material-add)    _req POST "/api/inspiration" "$(_read_body "$@")" ;;
  material-update) id="$1"; shift; _req PUT "/api/inspiration/${id}" "$(_read_body "$@")" ;;

  # ── 选题 ──
  topic-create) _req POST "/open-api/topic-cards" "$(_read_body "$@")" ;;
  topic-list)
    status="$(_opt --status "$@")"; page="$(_opt --page "$@")"
    q="pageNum=${page:-1}&pageSize=20"; [ -n "$status" ] && q="${q}&status=$(_enc "$status")"
    _req GET "/open-api/topic-cards?${q}" ;;
  topic-get)    _req GET "/open-api/topic-cards/$1" ;;
  topic-status) _req GET "/open-api/topic-cards/$1/generation-status" ;;

  # ── 文章 ──
  article-list)
    status="$(_opt --status "$@")"; page="$(_opt --page "$@")"
    q="pageNum=${page:-1}&pageSize=20"; [ -n "$status" ] && q="${q}&publishStatus=$(_enc "$status")"
    _req GET "/open-api/articles?${q}" ;;
  article-get) _req GET "/open-api/articles/$1" ;;
  to-publish)  _req GET "/open-api/articles/to-publish" ;;

  # ── 审稿（系统 articleId） ──
  review-run) _req POST "/api/reviews/start/$1" ;;
  review-get) _req GET  "/api/reviews/$1" ;;
  review-approve)
    id="$1"; shift; score="$(_opt --score "$@")"; comment="$(_opt --comment "$@")"
    body="{\"decision\":\"approve\""
    [ -n "$score" ]   && body="${body},\"score\":${score}"
    [ -n "$comment" ] && body="${body},\"comment\":$(_jstr "$comment")"
    body="${body}}"
    _req POST "/api/reviews/${id}/decision" "$body" ;;
  review-revise)
    id="$1"; shift; req="$(_opt --requirements "$@")"
    [ -z "$req" ] && { echo "❌ review-revise 需要 --requirements '...'" >&2; exit 1; }
    _req POST "/api/reviews/${id}/decision" "{\"decision\":\"revise\",\"requirements\":$(_jstr "$req")}" ;;

  # ── 改稿（bjArticleId） ──
  article-rewrite)
    id="$1"; shift; ins="$(_opt --instruction "$@")"
    _req POST "/open-api/bj-article/rewrite" "{\"articleId\":${id},\"instruction\":$(_jstr "$ins")}" ;;
  article-partial-edit)
    id="$1"; shift; sel="$(_opt --selected "$@")"; ins="$(_opt --instruction "$@")"
    _req POST "/open-api/bj-article/partial-edit" \
      "{\"articleId\":${id},\"selectedText\":$(_jstr "$sel"),\"instruction\":$(_jstr "$ins")}" ;;
  article-set-content)
    id="$1"; shift; _req PUT "/open-api/articles/${id}/content" "$(_read_body "$@")" ;;
  article-versions) _req GET "/open-api/bj-article/$1/versions" ;;
  article-rollback)
    id="$1"; shift; ver="$(_opt --version "$@")"
    _req POST "/open-api/bj-article/rollback" "{\"articleId\":${id},\"versionNumber\":${ver}}" ;;

  *) echo "未知命令: $cmd" >&2; echo >&2; usage >&2; exit 1 ;;
esac
