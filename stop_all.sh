#!/usr/bin/env bash
# run_all.sh로 띄운 서버들을 전부 종료.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_DIR="$ROOT/.run"

if [ ! -d "$PID_DIR" ]; then
  echo "실행 중인 서버 기록이 없습니다 (run_all.sh를 먼저 실행했는지 확인하세요)."
  exit 0
fi

for pidfile in "$PID_DIR"/*.pid; do
  [ -f "$pidfile" ] || continue
  name="$(basename "$pidfile" .pid)"
  pid="$(cat "$pidfile")"
  if kill -0 "$pid" 2>/dev/null; then
    # run_all.sh가 setsid로 띄워서 $pid == 새 프로세스 그룹 id이므로,
    # -$pid(그룹 kill)로 dotnet run이 띄운 자식 프로세스까지 함께 종료한다.
    kill -- "-$pid" 2>/dev/null || kill "$pid"
    echo "종료: $name (pid $pid)"
  else
    echo "이미 종료됨: $name"
  fi
  rm -f "$pidfile"
done
