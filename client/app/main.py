import asyncio
import os
import uuid

from app.api_server_client import ApiServerClient

HOST = os.environ.get("API_SERVER_HOST", "127.0.0.1")
PORT = int(os.environ.get("API_SERVER_PORT", "9000"))


#=== run_complaint_flow()함수 시작부분 한줄로 처리하지말고별도로 스레드 통해 분담하여처리

async def run_complaint_flow(client: ApiServerClient, loop: asyncio.AbstractEventLoop) -> None:
     async def ask(prompt: str) -> str:
         return (await loop.run_in_executor(None, input, prompt)).strip()

#=== 고소인/피고소인 정보 입력받기
     complainant_name = await ask("고소인 명칭(회사명 또는 성명)> ")
     complainant_representative = await ask("고소인 대표자(개인이면 여백으로 둘것)> ")
     complainant_address = await ask("고소인 주소> ")
     accused_name = await ask("피고소인 성명> ")
     accused_address = await ask("피고소인 주소> ")
     charge = await ask("죄명> ")
     incident_description = await ask("사건 설명(육하원칙으로)> ")

#===  입력받은 정보를 딕셔너리로 묶어서 서버에 보내기
     response = await client.send_complaint(
         {
             "complainant_name": complainant_name,
             "complainant_representative": complainant_representative,
             "complainant_address": complainant_address,
             "accused_name": accused_name,
             "accused_address": accused_address,
             "charge": charge,
             "incident_description": incident_description,
         }
    )

#=== 응답에서 문서 꺼내고, 실패 시 처리

     document = response.get("document")
     if document is None:
         print(f"생성 실패: {response}")
         return

#=== 파일저장하기
     filepath = os.path.join(os.getcwd(), f"고소장_{uuid.uuid4().hex[:8]}.md")
     with open(filepath, "w", encoding="utf-8") as f:
         f.write(document)
     print(f"저장됨: {filepath}")

#=== nain()함수시작 최상위 함수라서 들어쓰기 없음
async def main() -> None:
    client = ApiServerClient(HOST, PORT)
    await client.connect()
    print(f"연결됨 (session_id={client.session_id}). 빈 줄 입력 시 종료.")
    loop = asyncio.get_running_loop()

#=== 반복시작+질문 입력받기
    try:
        while True:
            rag_selector_query = (
                await loop.run_in_executor(None, input, "질문(또는/고소장 입력)> ")
            ).strip()

#=== 빈 줄 입력시 종료
            if not rag_selector_query:
                break
            if rag_selector_query == "/고소장":
                await run_complaint_flow(client, loop)
                continue

#=== 실제 질문 받고 답변 출력하기
            question = (await loop.run_in_executor(None, input, "실제 질문> ")).strip()
            response = await client.send_query(rag_selector_query, question)
            print(response)

#=== 종료 처리 및 실행부
    finally:
        await client.close()

if __name__ == "__main__":
    asyncio.run(main())
