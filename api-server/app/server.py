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

async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    peer = writer.get_extra_info("peername")
    print(f"[연결] {peer}")

#=== 상태 객체 및 백그라운드 작업

    state = ConnectionState(writer)
    pinger = asyncio.create_task(ping_loop(state))
    query_tasks: set[asyncio.Task] = set()

#=== 메시지 읽기 반복문 시작

    try:
        while line := await reader.readline():
            try:
                payload = json.loads(line)

#=== JSON 파싱 실패 시 처리:
            except json.JSONDecodeError:
                writer.write(b'{"error": "invalid JSON"}\n')
                await writer.drain()
                continue

#=== pong(응답 신호)
            if payload.get("type") == "pong":
                state.awaiting_pong = False
                state.missed_pongs = 0
                continue

#=== 일반 질문이면 처리 태스크 생성
            state.session_id = payload.get("session_id")
            task = asyncio.create_task(process_query(payload, state))
            query_tasks.add(task)

#=== 작업 끝나면 자동으로 바구니에게 제거
            task.add_done_callback(query_tasks.discard)

#=== 연결 종료 시 정리 시작
    finally:
        pinger.cancel()
        for task in query_tasks:
            task.cancel()

#=== 세션 정리
        if state.session_id is not None and sessions.get(state.session_id) is writer:
            del sessions[state.session_id]

#=== hande_client() 마무리, 연결닫기

        writer.close()
        await writer.wait_closed()
        print(f"[종료] {peer}")

#=== 서버 시작 함수 main()

async def main() -> None:
    server = await asyncio.start_server(handle_client, HOST, PORT)
    print(f"API Server 대기 중: {HOST}:{PORT} (MainServer: {MAIN_SERVER_URL})")

#=== 서버를 계속 켜두기:
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    asyncio.run(main())
