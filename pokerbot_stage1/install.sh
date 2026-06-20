#!/usr/bin/env bash
set -euo pipefail

SRC_REPO="Phenolemox/Main"
TARGET_REPO="Phenolemox/poker-bot"
TARGET_DIR="/opt/repos/poker-bot"
TMP_DIR="/tmp/pokerbot_stage1_main"

rm -rf "$TMP_DIR"
gh repo clone "$SRC_REPO" "$TMP_DIR" -- --depth 1

if [ ! -d "$TARGET_DIR/.git" ]; then
  rm -rf "$TARGET_DIR"
  gh repo clone "$TARGET_REPO" "$TARGET_DIR"
fi

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/${TARGET_REPO}.git"
git branch -M main

rsync -a --delete \
  --exclude '.git' \
  --exclude '.venv' \
  "$TMP_DIR/pokerbot_stage1/repo/" "$TARGET_DIR/"

python3 -m venv .venv
./.venv/bin/python -m pip install --upgrade pip
./.venv/bin/pip install -r requirements.txt
./.venv/bin/python -m py_compile $(find app -name '*.py')
./.venv/bin/python -m pytest -q

git config user.name >/dev/null 2>&1 || git config user.name "ai-server"
git config user.email >/dev/null 2>&1 || git config user.email "ai-server@local"

git add .
git commit -m "Bootstrap modular poker bot stage 1" || true
git push -u origin main

echo "===== POKER BOT STAGE 1 DONE ====="
git status --short
