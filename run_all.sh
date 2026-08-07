#!/usr/bin/env bash
# DBServer -> RagServer -> LLMServer -> MainServer -> API Server 순서로 전부 백그라운드 기동.
# Client는 대화형이라 이 스크립트에 포함하지 않음 — 다 뜬 뒤 별도로 `cd client && python3 -m app.main`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$ROOT/logs"
PID_DIR="$ROOT/.run"
mkdir -p "$LOG_DIR" "$PID_DIR"

DB_SERVER_PORT=5022
RAG_SERVER_PORT=8000
LLM_SERVER_PORT=5172
MAIN_SERVER_PORT=5087
API_SERVER_PORT=9000

fail() { echo "[실패] $1" >&2; exit 1; }
info() { echo "[정보] $1"; }

# --- 0. 사전 준비물 확인 ---
command -v dotnet >/dev/null 2>&1 || fail "dotnet(.NET SDK)이 설치되어 있지 않습니다."
command -v python3 >/dev/null 2>&1 || fail "python3가 설치되어 있지 않습니다."
command -v ollama >/dev/null 2>&1 || fail "ollama가 설치되어 있지 않습니다."

for model in bge-m3 llama3.2:3b; do
  ollama list 2>/dev/null | grep -q "^${model}" || fail "Ollama에 '$model' 모델이 없습니다. 'ollama pull $model'로 받으세요."
done

if [ ! -f "$ROOT/.env" ]; then
  fail "$ROOT/.env 파일이 없습니다. $ROOT/.env.example을 복사해 DB_PASSWORD를 채워 넣으세요."
fi
# shellcheck disable=SC1091
source "$ROOT/.env"
for var in DB_HOST DB_USER DB_PASSWORD DB_NAME; do
  [ -n "${!var:-}" ] || fail ".env에 $var 값이 비어있습니다."
done

RAG_DATA_ROOT="$HOME/rag1/my_rag1.2/RAG_project_Back_up"
for f in "RagFile/precedents_chunks.jsonl" "RagFile2/interpretations_chunks.jsonl" "RagFile3/adjudications_chunks.jsonl"; do
  [ -f "$RAG_DATA_ROOT/$f" ] || fail "RagServer 실 데이터 파일이 없습니다: $RAG_DATA_ROOT/$f"
done

# 이미 그 포트에서 뭔가 응답하고 있으면 "실행 중"으로 간주 — 중복 클릭 시 재기동 대신 건너뛴다.
port_open() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# --- 포트가 열릴 때까지 대기 (최대 TIMEOUT초) ---
wait_port() {
  local port="$1" name="$2" timeout="${3:-60}"
  local waited=0
  until curl -s -o /dev/null "http://localhost:$port" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    if [ "$waited" -ge "$timeout" ]; then
      fail "$name 가 ${timeout}초 안에 http://localhost:$port 에서 응답하지 않습니다. $LOG_DIR/$name.log 확인하세요."
    fi
  done
  info "$name 준비됨 (http://localhost:$port, ${waited}초 소요)"
}

# setsid로 새 프로세스 그룹을 만들어서 실행 — dotnet run은 실제 서버 바이너리를
# 자식 프로세스로 한 번 더 띄우는데, 그냥 kill $pid로는 이 자식이 안 죽고 남는다.
# setsid를 쓰면 dotnet run과 그 자식이 같은 새 그룹에 묶여서 stop_all.sh가
# `kill -- -$pid`(그룹 kill) 한 번으로 전부 정리된다.
start_dotnet() {
  local name="$1" dir="$2" port="$3"; shift 3
  if port_open "$port"; then
    info "$name 이미 실행 중으로 보여서 건너뜀 (http://localhost:$port 응답함)"
    return
  fi
  info "$name 시작 중..."
  ( cd "$ROOT/$dir" && exec setsid "$@" dotnet run > "$LOG_DIR/$name.log" 2>&1 ) &
  echo $! > "$PID_DIR/$name.pid"
  wait_port "$port" "$name"
}

# --- 1. DBServer ---
start_dotnet "db-server" "db-server" "$DB_SERVER_PORT" \
  env "DB_HOST=$DB_HOST" "DB_USER=$DB_USER" "DB_PASSWORD=$DB_PASSWORD" "DB_NAME=$DB_NAME"

# --- 2. RagServer ---
if port_open "$RAG_SERVER_PORT"; then
  info "rag-server 이미 실행 중으로 보여서 건너뜀 (http://localhost:$RAG_SERVER_PORT 응답함)"
else
  info "rag-server 시작 중..."
  ( cd "$ROOT/rag-server" && exec setsid "$ROOT/rag-server/.venv/bin/uvicorn" app.main:app --port "$RAG_SERVER_PORT" \
     > "$LOG_DIR/rag-server.log" 2>&1 ) &
  echo $! > "$PID_DIR/rag-server.pid"
  wait_port "$RAG_SERVER_PORT" "rag-server" 90
fi

# --- 3. LLMServer ---
start_dotnet "llm-server" "llm-server" "$LLM_SERVER_PORT"

# --- 4. MainServer ---
start_dotnet "main-server" "main-server" "$MAIN_SERVER_PORT" \
  env "RAG_SERVER_URL=http://localhost:$RAG_SERVER_PORT" \
      "LLM_SERVER_URL=http://localhost:$LLM_SERVER_PORT" \
      "DB_SERVER_URL=http://localhost:$DB_SERVER_PORT"

# --- 5. API Server ---
if port_open "$API_SERVER_PORT"; then
  info "api-server 이미 실행 중으로 보여서 건너뜀 (http://localhost:$API_SERVER_PORT 응답함)"
else
  info "api-server 시작 중..."
  ( cd "$ROOT/api-server" && exec setsid env MAIN_SERVER_URL="http://localhost:$MAIN_SERVER_PORT" API_SERVER_PORT="$API_SERVER_PORT" \
     "$ROOT/api-server/.venv/bin/python3" -m app.server \
     > "$LOG_DIR/api-server.log" 2>&1 ) &
  echo $! > "$PID_DIR/api-server.pid"
  sleep 3
  kill -0 "$(cat "$PID_DIR/api-server.pid")" 2>/dev/null || fail "api-server 시작 실패. $LOG_DIR/api-server.log 확인하세요."
  info "api-server 준비됨 (http://localhost:$API_SERVER_PORT)"
fi

echo
echo "=== 전부 기동 완료 ==="
echo "DBServer   : http://localhost:$DB_SERVER_PORT"
echo "RagServer  : http://localhost:$RAG_SERVER_PORT"
echo "LLMServer  : http://localhost:$LLM_SERVER_PORT"
echo "MainServer : http://localhost:$MAIN_SERVER_PORT"
echo "API Server : http://localhost:$API_SERVER_PORT"
echo
echo "Client 실행: cd client && python3 -m app.main"
echo "전부 종료  : ./stop_all.sh"
echo "로그 위치  : $LOG_DIR/"
