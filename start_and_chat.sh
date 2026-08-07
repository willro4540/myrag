#!/usr/bin/env bash
# 한 번의 실행으로 백엔드 5개 기동 + 채팅 GUI까지 자동 실행.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$ROOT/run_all.sh"
exec "$ROOT/run_gui.sh"
