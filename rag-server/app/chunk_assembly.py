"""청크(조각)로 나뉘어 들어오는 요청을 session_id 기준으로 모아 완성 여부를 판단한다."""


class ChunkAssembly:
    def __init__(self):
        self._chunks: dict[int, str] = {}
        self._final_request_number: int | None = None
