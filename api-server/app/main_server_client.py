import httpx

CHUNK_SIZE = 20 # MainServer/RagServer 프로토콜은 그대로라, 여기서 이 글자 수만큼씩 나눠보낸다.

class MainServerClient:
    def __init__(self, base_url: str):
        self._client = httpx.AsyncClient(base_url=base_url, timeout=120)

#=== query() 메서드 시작(매개변수 선언, 여러 줄로 나눠씀):
    async def query(
        self,
        session_id: str,
        rag_selector_query: str,
        question: str,
        message_count: int,
        history: list[dict],
    ) -> dict:

#=== 질문을 20자씩 자르는 부분(2줄):
        chunks = [question[i : i + CHUNK_SIZE] for i in range(0, len(question), CHUNK_SIZE)] or [""]
        final_request_number = len(chunks)


        result: dict | None = None
        for request_number, message_chunk in enumerate(chunks, start=1):

#=== 매 조각마다 보낼 데이터 만들기
            payload = {
                "session_id": session_id,
                "request_number": request_number,
                "message_chunk": message_chunk,
                "is_complete": request_number == final_request_number,
            }

#=== 첫번째 조각에만 추가 정보를 붙이기
            if request_number == 1:
                payload["rag_selector_query"] = rag_selector_query
                payload["final_request_number"] = final_request_number
                payload["message_count"] = message_count
                payload["history"] = history


#=== 실제로 HTTP 요청 보내고 결과 저장하기
            response = await self._client.post("/query", json=payload)
            response.raise_for_status()
            result = response.json()

        return result

#=== 마지막 메서드
    async def complaint(self, payload: dict) -> dict:
        response = await self._client.post("/complaint", json=payload)
        response. raise_for_status()
        return response.json()
