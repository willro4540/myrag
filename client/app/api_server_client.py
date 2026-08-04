import asyncio
import json
import uuid

class ApiServerClient:
    """API Server와의 연결 하나 = 세션 (대화) 하나."""

#=== 메서드 host/port저장하고 session_id 생성저
    def __init__(self, host: str, port: int):
        self._host = host
        self._port = port
        self.session_id = str(uuid.uuid4())

#===  안내판/규칙, _(언더스코어)관례상 사용하지만 절대로 건들지말라는 주의하는 표시
        self._reader: asyncio.StreamReader | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._responses: asyncio.Queue[dict] = asyncio.Queue()
        self._reader_task: asyncio.Task | None = None
        self._closed_event = asyncio.Event()
        self._message_count = 0
        self._history: list[dict] = []

#=== connect() 메서드, 기다리는 동안 다른 일도 동시에 가능한 함수라는 표시
    async def connect(self) -> None:
        self._reader, self._writer = await asyncio.open_connection(self._host, self._port)
        self._reader_task = asyncio.create_task(self._read_loop())

#=== _rea_loop() 연결이 끊기기 전까지 무한 반복하면서 서벅가 보낸 메시지를 한줄씩읽고 ping으로 답하고 대기줄인_responses에 넣는다. 반복이 끝나면 에러든 정상 종료 든 마지막에" 연결 끊김" 신호를 켠다.
    async def _read_loop(self) -> None:
        try:
            while line := await self._reader.readline():
                message = json.loads(line)
                if message.get("type") == "ping":
                    await self._write({"type": "pong"})
                    continue
                await self._responses.put(message)

#=== except(문제 생겼을 떄 대처)와  finally(무슨 일이 있었든 무조건 실행)===
        except asyncio.CancelledError:
            raise
        except Exception:
            pass
        finally:
            self._closed_event.set()

#=== _write() -서버한테 실제로 데이터를 보내는 부분=====
    async def _write(self, payload: dict) -> None:
        self._writer.write((json.dumps(payload, ensure_ascii=False) + "\n").encode())
        await self._writer.drain()

#=== _wait_for_response()-가장중요한 메서드
    async def _wait_for_response(self) -> dict:
         get_response = asyncio.create_task(self._responses.get())
         connection_closed = asyncio.create_task(self._closed_event.wait())

         try:
             done, pending = await asyncio.wait(
                 {get_response, connection_closed}, return_when=asyncio.FIRST_COMPLETED
             )

             for task in pending:
                 task.cancel()
             if get_response in done:
                 return get_response.result()
             raise ConnectionError("API Server와의 연결이 끊어짐")

         finally:
             get_response.cancel()
             connection_closed.cancel()

    async def send_query(self, rag_selector_query: str, question: str) -> dict:
        self._message_count += 1 # 이세션에서 몇 번째 메시지인지 확인

        await self._write(
            {
                 "session_id": self.session_id,
                 "rag_selector_query": rag_selector_query,
                 "question": question,
                 "message_count": self._message_count,
                 "history": self._history,
            }
        )

        response = await self._wait_for_response()
        answer = response.get("result")
        if answer is not None:
            self._history.append({"question": question, "answer": answer})
        return response

# **fields 일종의 툴 청킹작업과 다르게 글자를 합쳐 서버로 보내는 방식
    async def send_complaint(self, fields: dict) -> dict:
        await self._write({"type": "complaint", "session_id": self.session_id, **fields})
        return await self._wait_for_response()

    async def close(self) -> None:
        self._reader_task.cancel() # _read_loop()루프를 그만하라고 지시
        self._writer.close() # 서버와의 연결을 끊겠다고 신호
        await self._writer.wait_closed() # 완전히 신호가 끊겼는지 확인


