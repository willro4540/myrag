#!/usr/bin/env bash
# 새 컴퓨터(예: 개인 노트북)에서 myrag를 처음 세팅하는 스크립트.
# Ubuntu/Debian 계열 전용 (apt 사용). git으로 이 저장소를 받은 뒤 1회 실행.
# 이미 있는 항목은 건너뛰므로 여러 번 실행해도 안전함.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() { echo "[실패] $1" >&2; exit 1; }
info() { echo "[정보] $1"; }

echo "=== myrag 셋업 시작 ==="

# --- 1. 시스템 패키지 ---
if ! command -v dotnet >/dev/null 2>&1; then
  info "dotnet SDK가 없어서 설치를 시도합니다 (sudo 비밀번호 필요)."
  fail "dotnet SDK를 직접 설치해주세요: https://learn.microsoft.com/dotnet/core/install/linux-ubuntu (배포판마다 방법이 달라 자동 설치는 생략)"
fi

if ! command -v python3 >/dev/null 2>&1; then
  sudo apt-get update && sudo apt-get install -y python3 python3-venv python3-pip
fi

if ! command -v mysql >/dev/null 2>&1; then
  info "mysql-server가 없어서 설치합니다 (sudo 비밀번호 필요)."
  sudo apt-get update && sudo apt-get install -y mysql-server
  sudo systemctl enable --now mysql
fi

if ! command -v ollama >/dev/null 2>&1; then
  info "ollama가 없어서 설치합니다."
  curl -fsSL https://ollama.com/install.sh | sh
fi

for model in bge-m3 llama3.2:3b; do
  ollama list 2>/dev/null | grep -q "^${model}" || { info "ollama pull $model ..."; ollama pull "$model"; }
done

# --- 2. 개인 MySQL DB 세팅 (myrag_db / myrag_user) ---
DB_NAME="myrag_db"
DB_USER="myrag_user"

if [ -f "$ROOT/.env" ]; then
  info "$ROOT/.env 가 이미 있어서 DB 생성 단계는 건너뜁니다."
  info "(팀 DB에서 개인 DB로 바꾸려는 거라면, 이 스크립트 실행 전에 기존 .env를 다른 이름으로 옮겨두세요: mv .env .env.bak)"
else
  echo "새로 만들 MySQL 계정(${DB_USER})의 비밀번호를 정해주세요."
  read -r -s -p "비밀번호: " DB_PASSWORD
  echo
  [ -n "$DB_PASSWORD" ] || fail "비밀번호가 비어있습니다."

  info "MySQL에 ${DB_NAME} 데이터베이스 + ${DB_USER} 계정 생성 중 (sudo 비밀번호가 필요할 수 있음)..."
  sudo mysql <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

  info "테이블 생성 중 (db_schema.sql)..."
  mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "$ROOT/db_schema.sql"

  cat > "$ROOT/.env" <<ENV
DB_HOST=127.0.0.1
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=${DB_NAME}
ENV
  cp "$ROOT/.env" "$ROOT/adminclient/.env"
  info ".env 생성 완료 (루트 + adminclient) — DB_HOST=127.0.0.1, DB_NAME=${DB_NAME}"
fi

# --- 3. Python venv: rag-server / api-server (각자 필요한 패키지만) ---
for dir in rag-server api-server; do
  if [ ! -d "$ROOT/$dir/.venv" ]; then
    info "$dir 용 venv 생성 중..."
    python3 -m venv "$ROOT/$dir/.venv"
    "$ROOT/$dir/.venv/bin/pip" install -q -r "$ROOT/$dir/requirements.txt"
  fi
done

# --- 4. Python venv: GUI 전용 (gui_handler + adminclient 공용, PySide6 등) ---
if [ ! -d "$ROOT/.venv-gui" ]; then
  info "GUI용 venv(.venv-gui) 생성 중 (PySide6 등, 시간 걸림)..."
  python3 -m venv "$ROOT/.venv-gui"
  "$ROOT/.venv-gui/bin/pip" install -q \
    -r "$ROOT/gui_handler/requirements.txt" \
    -r "$ROOT/adminclient/requirements.txt"
fi

echo
echo "=== 셋업 완료 ==="
echo "다음 단계: ./run_all.sh (또는 ./start_and_chat.sh) 로 기동"
