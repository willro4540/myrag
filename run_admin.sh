#!/usr/bin/env bash
# 통계창(adminclient) 실행. 채팅 체인(run_all.sh)과 완전히 독립적 — DB에 직접 붙어 읽기 전용 통계만 보여줌.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$ROOT/.venv-gui"

fail() { echo "[실패] $1" >&2; exit 1; }
info() { echo "[정보] $1"; }

[ -f "$ROOT/adminclient/.env" ] || fail "$ROOT/adminclient/.env 파일이 없습니다. ./setup.sh를 먼저 실행하거나 adminclient/.env.example을 복사해 DB_PASSWORD를 채워 넣으세요."

if [ ! -d "$VENV" ]; then
  info "GUI용 venv(.venv-gui)가 없어서 새로 만듭니다..."
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q -r "$ROOT/gui_handler/requirements.txt" -r "$ROOT/adminclient/requirements.txt"
fi

cd "$ROOT/adminclient"
"$VENV/bin/python3" main.py
