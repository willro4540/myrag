#!/usr/bin/env bash
# 채팅 GUI(gui_handler) 실행. 백엔드 5개 서버(run_all.sh)가 먼저 떠 있어야 실제 답변을 받을 수 있음.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$ROOT/.venv-gui"

fail() { echo "[실패] $1" >&2; exit 1; }

[ -f "$ROOT/.env" ] || fail "$ROOT/.env 파일이 없습니다. ./setup.sh를 먼저 실행하거나 .env.example을 복사해 DB_PASSWORD를 채워 넣으세요."
# shellcheck disable=SC1091
source "$ROOT/.env"
for var in DB_HOST DB_USER DB_PASSWORD DB_NAME; do
  [ -n "${!var:-}" ] || fail ".env에 $var 값이 비어있습니다."
done

if [ ! -d "$VENV" ]; then
  info() { echo "[정보] $1"; }
  info "GUI용 venv(.venv-gui)가 없어서 새로 만듭니다..."
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q -r "$ROOT/gui_handler/requirements.txt" -r "$ROOT/adminclient/requirements.txt"
fi

cd "$ROOT/gui_handler"
PYTHONPATH="$ROOT" DB_HOST="$DB_HOST" DB_USER="$DB_USER" DB_PASSWORD="$DB_PASSWORD" DB_NAME="$DB_NAME" \
  "$VENV/bin/python3" -m gui.main
