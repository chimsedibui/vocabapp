# 08 — Trích từ vựng từ passage theo trình độ

Bổ sung yêu cầu ngày 19/10/2026, kickoff v0.2. FR15 / UC10, P0 trong M2. Đây là đặc tả, chưa phải chức năng đã chạy.

## 1. Luồng sử dụng

**Dán passage → chọn ngưỡng CEFR → trích xuất → xem JSON/danh sách → duyệt → thêm vào nhóm.**

Người dùng dán một hoặc nhiều đoạn văn thành một passage, chọn ngôn ngữ nguồn/nghĩa, nhóm đích, mức tối thiểu (mặc định B1) và số mục tối đa (mặc định 30, tối đa 100). V1 tập trung Anh → Việt; chưa bao gồm upload PDF, OCR hay crawl URL.

Quy tắc lọc của sản phẩm: thứ tự A1 < A2 < B1 < B2 < C1 < C2; B1 trở lên bao gồm B1, B2, C1, C2. Nhãn trình độ do LLM **ước lượng theo nghĩa trong ngữ cảnh**, không phải chứng nhận hoặc ánh xạ từ điển chính thức. Không chắc mức thì bỏ qua trong chế độ tiết kiệm; UI luôn cho sửa/bỏ kết quả. Không hứa liệt kê đầy đủ mọi từ đạt ngưỡng.

LLM chỉ lấy từ/cụm từ có mặt trong passage, ưu tiên từ hữu ích để học, bỏ tên riêng/số/URL và trùng cùng nghĩa. Phrasal verb/cụm từ cố định được phép; không trả cả câu dài làm “từ”. V1 trả đúng dạng xuất hiện trong passage để kiểm chứng cục bộ; chuẩn hóa lemma là mở rộng sau. Một dạng có nhiều nghĩa trong passage có thể xuất hiện nhiều mục nếu nghĩa khác; không gộp chỉ dựa vào term.

## 2. UC10 — Thêm từ từ đoạn văn

**Actor:** admin/người học. **Tiền điều kiện:** có passage và một LLM provider đã cấu hình; không cần có nhóm sẵn.

1. Dán passage, chọn mức tối thiểu và giới hạn số từ, chọn/tạo nhóm đích.
2. App kiểm tra trống/độ dài, ước tính input tokens, hiển thị provider và giới hạn output trước khi gọi. Không gọi khi đang gõ.
3. Gửi passage một lần cho LLM cùng yêu cầu ngắn: trích từ, ước lượng mức và nghĩa ngắn trong cùng request.
4. Nhận JSON theo contract tối giản; validate và lọc mức lần nữa bằng code. Đối chiếu term có trong passage sau chuẩn hóa Unicode/khoảng trắng và word boundaries; không match một từ như `he` bên trong `the`.
5. Hiển thị kết quả ở bảng chờ duyệt, gắn nhãn mức ước lượng; có nút xem/copy JSON. Tra DB cục bộ để đánh dấu đã có/xung đột, không gửi toàn thư viện lên LLM.
6. Người dùng chọn nghĩa cần giữ, sửa nếu cần, duyệt; app thêm membership/entry/sense theo quy tắc dữ liệu, không tự ghi đè hoặc reset tiến độ.

**Ngoại lệ:** `{"items":[]}` là thành công không tìm thấy mục phù hợp, không tự gọi lại. JSON lỗi/truncated/refusal không được coi là danh sách rỗng thành công. Nếu đủ `max_items`, hiển thị “đã đạt giới hạn, có thể còn từ khác”; không tự gọi “tiếp tục”. Kết quả đạt schema nhưng term không có trong nguồn hoặc mức dưới ngưỡng bị loại và báo số mục loại; không tự gọi sửa để bù đủ số lượng.

Azure/OpenAI có thể dự phòng cho nhau theo chính sách hiện có. **Google Translation không thay thế bước trích xuất và phân mức.** Nếu cả LLM không khả dụng, giữ passage để thử lại hoặc cho người dùng tự chọn từ rồi dùng luồng dịch Google thông thường; không gửi cả passage sang Google và tuyên bố đã lọc B1+.

## 3. Output JSON mặc định

Contract response v1 chỉ có `items`, mỗi mục đúng 3 trường:

```json
{"items":[{"term":"persistent","level":"B2","meaning":"dai dẳng"}]}
```

Ví dụ chỉ minh họa cấu trúc và nhãn ước lượng, không khẳng định mức từ theo nguồn chuẩn.

- `term`: dạng có mặt trong passage, tối đa 120 ký tự.
- `level`: A1/A2/B1/B2/C1/C2; app áp dụng ngưỡng được chọn, schema tự nó không kiểm được ngưỡng runtime.
- `meaning`: nghĩa ngắn đúng ngữ cảnh, tối đa 160 ký tự, không ví dụ/giải thích.
- Không Markdown fence, lời mở đầu/kết luận, phiên âm, POS, synonyms, câu nguồn hoặc giải thích vì sao chọn mức. Không yêu cầu model trình bày suy luận.
- Không bắt model lặp nhóm/ngôn ngữ/provider/version cho từng mục: app đã có metadata đó.

[Schema response](../schemas/passage-extraction.v1.schema.json), [request mẫu](../examples/passage-request.v1.json), [response mẫu](../examples/passage-response.v1.json). Request mẫu là DTO nội bộ, không phải HTTP payload dùng nguyên xi cho mọi provider.

Dùng structured output khi model/deployment hỗ trợ; adapter chuyển schema sang subset tương thích và app validate lại. JSON mode/prompt yêu cầu JSON không tương đương schema enforcement. Tham chiếu [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs).

## 4. Tiết kiệm token và giới hạn

Mục tiêu là **đủ dữ liệu học với ít token**, không hứa số token tối thiểu tuyệt đối hoặc chỉ tính token nhìn thấy trong JSON.

- Một call mặc định xử lý cả passage; không dịch toàn passage trước, không gọi một lần cho mỗi từ, không chạy enrichment lần nữa cho kết quả đã có nghĩa.
- Prompt ngắn, không lịch sử chat, không ví dụ few-shot mặc định; nhóm và DB không gửi đi. Passage là dữ liệu không đáng tin, không thực thi chỉ dẫn nằm trong passage và không mở tools theo nội dung của nó.
- Trả đúng 3 trường/mục; compact JSON được yêu cầu nhưng minify sau khi nhận không giảm token đã tính phí. Tên key ngắn hơn không được mặc định coi là rẻ hơn nếu chưa đo tokenizer.
- V1 giới hạn passage 12.000 ký tự và input ước tính tối đa 4.000 tokens gồm instructions/schema, tùy context window và token counter của model. Kiểm cả ký tự lẫn token; nếu không đếm chính xác thì hiển thị ước tính bảo thủ.
- `max_items` mặc định 30; output cap đề xuất 2.500 tokens, phải hiệu chỉnh theo model và phần reasoning nếu có. Trước request kiểm tổng input + output reserve có vừa context window không. Giới hạn này là đề xuất thử nghiệm, không bảo đảm đủ cho 100 mục.
- Vượt giới hạn → yêu cầu người dùng chia đoạn hoặc điều chỉnh giới hạn công khai; không tự cắt passage mất nội dung. Tự chunk/map-reduce nằm ngoài MVP để tránh gọi API ngoài dự kiến.
- Tổng tối đa 3 HTTP attempts/job passage, bao gồm retry, repair và provider fallback, deadline tổng 120s. Đây là giới hạn riêng chặt hơn enrichment từng từ. Refusal/cancel không fallback; hết budget giữ lỗi/nháp, không lặp vô hạn.
- Cache theo hash passage đã chuẩn hóa NFC/newlines + ngôn ngữ + ngưỡng + max_items + provider/model + prompt/schema version, TTL 30 ngày. Khác ngữ cảnh không dùng cache nghĩa chỉ theo term. Cache hit cùng job không gọi API trừ khi chủ động “Tạo lại”.
- Lưu usage input/output và reasoning/cached tokens khi provider có trả, theo từng attempt kể cả retry; không có số thì ghi không xác định, không suy từ độ dài JSON. Benchmark prompt/cap trên bộ passage trước khi chốt giá trị.

## 5. Dữ liệu và ánh xạ vào thư viện

Thêm `PassageJob`: id, passage_text local, source_hash, source/target language, min_level, max_items, provider/model, prompt/schema_version, status, attempts, usage, created_at. Chỉ log hash/job ID; không log nguyên passage. Passage local được giữ đến khi người dùng xóa, có tùy chọn xóa sau khi duyệt; xóa nguồn không xóa từ đã nhận. Nếu giữ passage thì backup phải bao gồm và UI backup thông báo có văn bản nguồn.

Mỗi proposal lưu `estimated_level`, `level_source=llm`, `passage_job_id`, metadata provider. Khi duyệt, lưu mức và nguồn trên provenance của sense/revision, không coi mức là độ khó cá nhân của card. Thuật toán lịch ôn vẫn theo review, không theo CEFR.

Response compact không phải file import v1. App gắn deck/ngôn ngữ từ job, đề xuất `sense_key` local theo quy trình duyệt. Nếu chưa có entry: tạo key local; nếu đã có entry và nghĩa trùng chính xác sau chuẩn hóa thì gắn nhóm; nếu nghĩa khác/chưa chắc thì người dùng chọn sense cũ hoặc tạo sense mới. Không tự tạo `primary` rồi ghi đè. Mọi mục vẫn chờ duyệt.

Giữ nguyên schema import v1 hiện có; JSON export theo chuẩn import dùng adapter bổ sung trường bắt buộc và không kèm level/provenance vì v1 chưa hỗ trợ. Muốn giữ đủ metadata nguồn và trình độ dùng backup (mở rộng version DB/backup khi implementation), không hứa export từ vựng v1 round-trip metadata mới.

## 6. UAT bổ sung

| ID | Tình huống | Kỳ vọng |
|---|---|---|
| U21 | Chọn B1+, mock trả A2/B1/B2/C1/C2 | Loại A2; giữ mức từ B1, không chỉ B1 |
| U22 | Gửi passage hợp lệ, LLM trả kết quả | Chỉ JSON 3 field/item, không gọi enrichment bổ sung; vẫn chờ duyệt |
| U23 | Không có từ đạt ngưỡng | items rỗng, không tự retry/fallback |
| U24 | JSON lỗi/cắt dở/refusal | Không tạo thẻ; retry chỉ trong attempt budget; refusal không fallback |
| U25 | Cả LLM lỗi nhưng Google có key | Không tuyên bố Google trích/phân mức; cho tự chọn từ để dịch |
| U26 | Trích lại cùng passage/settings | Cache hit; không nhân entry/card hoặc reset schedule |
| U27 | Passage vượt input budget; nhiều kết quả vượt max_items | Chặn trước gửi nếu input quá dài; output vượt max_items bị từ chối contract, không commit âm thầm |
| U28 | Passage chứa “ignore instructions” hoặc model bịa từ ngoài đoạn | Chỉ coi là dữ liệu; từ ngoài passage bị loại, không hành động theo chỉ dẫn |
| U29 | Từ có sẵn nhưng nghĩa ngữ cảnh khác | Conflict review; không ghi đè sense cũ |
| U30 | Hết output cap/attempt budget hoặc cancel | Trạng thái lỗi/nháp rõ, không coi như đã trích đầy đủ |

Kiểm thử model thật sau M0 bằng tập passage do người dùng chọn: đánh giá độ đúng nghĩa, từ ngoài nguồn, mức ước lượng và tổng tokens/attempt. Schema hợp lệ không chứng minh chất lượng phân loại. Các test mock/schema trong kickoff chỉ kiểm hợp đồng dữ liệu.
