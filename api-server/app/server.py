import asyncio
import json
import os

from app.main_server_client import MainServerClient

HOST = os.environ.get("API_SERVER_HOST", "127.0.0.1")
PORT = int(os.environ.get("API_SERVER_PORT", "9000"))
MAIN_SERVER_URL = os.environ.get("MAIN_SERVER_URL", "http://localhost:8080")

PING_INTERVAL_SEC = 10
MAX_MISSED_PONGS = 3

main_server = MainServerClient(MAIN_SERVER_URL)

sessions: dict[str, asyncio.StreamWriter] = {}

class ConnectionState:
    def __init__(self, writer: asyncio.StreamWriter):
        self.writer = writer
        self.session_id: str | None = None
        self.awaiting_pong = False
        self.missed_pongs = 0

#=== ping을 주기적으로 보내는 함수
async def ping_loop(state: ConnectionState) -> None:
    try:
        while True:
            await asyncio.sleep(PING_INTERVAL_SEC)

            if state.awaiting_pong:
                state.missed_pongs += 1
                if state.missed_pongs >= MAX_MISSED_PONGS:
                    print(f"[핑퐁 {MAX_MISSED_PONGS}회 미수신] session_id={state.session_id} 연결 종료")
                    state.writer.close()
                    return
#===  ping 실제로 보내기 + 에러 처리 ping_loop() 마무리
            state.awaiting_pong = True
            state.writer.write(b'{"type": "ping"}\n')
            await state.writer.drain()
    except (ConnectionError, OSError):
        return

#===  질의 처리 함수 시작
async def process_query(payload: dict, state: ConnectionState) -> None:
    session_id = payload.get("session_id")
    if session_id is not None:
        sessions[session_id] = state.writer

#=== 어떤 요청인지 구분해서 MainServer 호출하기
    try:
        if payload.get("type") == "complaint":
            result = await main_server.complaint(payload)
        else:
            result = await main_server.query(
                session_id,
                payload.get("rag_selector_query", ""),
                payload.get("question", ""),
                payload.get("message_count", 1),
                payload.get("history", []),
            )

    except Exception as exc:
        result = {"error": str(exc)}

#=== 처리결과를 클라이언트에게 돌려보내기

    target = sessions.get(session_id, state.writer)
    try:
        target.write((json.dumps(result, ensure_ascii=False) + "\n").encode())
        await target.drain()
    except (ConnectionError, OSError):
        pass
