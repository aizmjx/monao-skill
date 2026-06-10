#!/usr/bin/env bash
#
# package.sh — 打 monao-create 发布包
# 用法: ./package.sh <version>   如 ./package.sh 1.0.0
# 产物: dist/monao-create-v<version>.tar.gz（顶层目录 monao-create/，只含 SKILL.md + scripts/）
#
set -euo pipefail

VERSION="${1:?用法: ./package.sh <version>  如 ./package.sh 1.0.0}"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_NAME="monao-create"
OUT_DIR="${SELF_DIR}/dist"
OUT_FILE="${OUT_DIR}/${SKILL_NAME}-v${VERSION}.tar.gz"

bash -n "${SELF_DIR}/scripts/monao.sh"   # 打包前先做语法检查

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "${STAGE}/${SKILL_NAME}"
cp "${SELF_DIR}/SKILL.md" "${STAGE}/${SKILL_NAME}/"
cp -R "${SELF_DIR}/scripts" "${STAGE}/${SKILL_NAME}/scripts"

mkdir -p "$OUT_DIR"
tar -czf "$OUT_FILE" -C "$STAGE" "$SKILL_NAME"

echo "✅ ${OUT_FILE}"
tar -tzf "$OUT_FILE"
