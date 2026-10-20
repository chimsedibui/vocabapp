# 13 — API và passage ở bản 0.3

Triển khai ngày 19/10/2026. Phần này ghi hành vi thực tế, bổ sung cho đặc tả mục tiêu tại tài liệu 08.

## Cách dùng

1. Cài đặt → API trích từ vựng → nhập key và tên model OpenAI, hoặc key + endpoint resource + tên deployment Azure OpenAI. Azure dùng API v1, endpoint dạng `https://TEN.openai.azure.com`; adapter cũ dự án 1 dùng API-version theo deployment chưa được port. Không tự tìm/copy key từ dự án 1.
2. Nhập đúng context window theo model. Mặc định 16.384 chỉ là cấu hình khởi tạo bảo thủ, không phải cam kết về model cụ thể. Dùng model hỗ trợ Chat Completions và Structured Outputs; có thể tắt Structured Outputs nếu model chỉ hỗ trợ JSON mode. App không tự đổi chế độ sau lỗi 400.
3. Có thể bật dịch vụ dự phòng, nhập đầy đủ cấu hình riêng. Lưu cấu hình không gọi API. Key/cấu hình nằm trong secure storage hệ điều hành; không nằm trong SQLite, backup, log hoặc GitHub. Học offline vẫn dùng được khi chưa cấu hình.
4. Thư viện → Từ passage (AI). Dán tiếng Anh, chọn mức tối thiểu (B1 mặc định), tối đa 1–100 mục (mặc định 30). Trước khi gửi, UI hiện dịch vụ chính/dự phòng và ngân sách input/output. Chỉ bấm Trích từ mới gửi văn bản ra dịch vụ.
5. Duyệt các mục được giữ, sửa nghĩa/mức, bỏ chọn mục không muốn học. Nhãn CEFR là ước lượng, chưa có benchmark phân loại bằng model thật. Term được giữ cố định theo kết quả đã kiểm nguồn; muốn thêm từ khác dùng luồng nhập tay. Với từ có sẵn, chọn giữ nghĩa hiện có hoặc dùng nghĩa đề xuất; nghĩa trùng chính xác sau NFC/trim được tái sử dụng, nghĩa khác tạo sense riêng.
6. Chọn/tạo nhóm, duyệt để đưa vào học. Toàn bộ lựa chọn commit cùng một transaction. Chưa duyệt thì chưa có card; duyệt lại không nhân card hoặc reset tiến độ. JSON hiển thị/copy gồm các mục đang chọn, chỉ term/level/meaning. Khi chọn giữ nghĩa cũ, nghĩa đó được dùng để học; JSON vẫn là bản đề xuất đang duyệt.

## Ngân sách, lỗi và cache

- Một request gồm system instruction ngắn + passage, không gửi thư viện, lịch sử chat hoặc ví dụ; không khai báo tools. Output cap 2.500 `max_completion_tokens`; reasoning tokens nếu có dùng chung cap. Không gọi enrichment lần nữa cho từng từ.
- Giới hạn 12.000 ký tự và input ước tính tối đa 4.000 tokens. Chưa tích hợp tokenizer cho từng model: dùng tổng số byte UTF-8 của instruction/passage/schema cộng 256 cho framing làm ước tính rất bảo thủ. Vì vậy đoạn ASCII vài nghìn ký tự có thể chạm ngân sách trước giới hạn 12.000. Đây không phải usage thực tế hoặc báo giá. Kiểm input ước tính + 2.500 với context window trước gửi, không tự cắt/chunk đoạn.
- Tối đa 3 HTTP attempts/job: chính, retry chính, dự phòng nếu bật (nếu không, vẫn chính). Auth/config 400/401/403/404 không retry cùng cấu hình, chuyển thẳng dự phòng nếu có. Dự phòng cũng không được tự gửi nếu chưa bật. Deadline tổng khoảng 120 giây, timeout từng attempt tối đa 40 giây, response tối đa 256 KiB, không theo redirect mang key.
- Refusal/content filter, hủy và output chưa hoàn tất/truncated không retry/fallback. `items:[]` là thành công không tìm thấy từ, không tự gọi tiếp. Khi lỗi ghi usage local, không gọi request trả phí tiếp theo.
- Kiểm contract chính xác 3 trường, chuỗi không rỗng, giới hạn độ dài, enum CEFR và max_items. Sau đó loại mức thấp, term ngoài passage, trùng term/nghĩa. Đối chiếu nguồn sau NFC, gộp khoảng trắng, không phân biệt hoa/thường; dùng ranh giới Unicode để không match `he` trong `the` hoặc mảnh của từ có dấu nháy/gạch nối. Đủ max_items thì cảnh báo có thể còn từ.
- Cache 30 ngày theo hash nguồn NFC/newlines + mức/số mục + provider/endpoint/model/context/mode + prompt/schema version. Key bí mật và nhóm không thuộc cache key. Nút Tạo lại chủ động bỏ cache. Cache hiện được tái sử dụng khi cấu hình API còn đọc được; khi không có key có thể mở lại kết quả cũ trong lịch sử mà không gọi mạng.
- Lưu usage số input/output/total và cached/reasoning details nếu provider trả; không có thì `null`, không suy từ độ dài JSON. Response lỗi không có usage thì chi phí không xác định. Không log response/raw passage. UI Xem usage mở accounting JSON local của job.

## Dữ liệu và tương thích

DB version 2 thêm passage_jobs (nguồn, settings, hash, kết quả, attempts/usage/trạng thái) và sense_origins (job, mức được duyệt, nguồn mức llm/user, provider/model). Chỉnh CEFR khi duyệt ghi level_source=user; không lấy CEFR làm độ khó cá nhân của thuật toán ôn. Giữ nguyên nghĩa cũ khác nghĩa AI thì không gắn nhãn CEFR AI cho nghĩa cũ đó.

Lịch sử hiển thị 30 job gần nhất; giữ nguồn trên thiết bị đến khi người dùng xóa. Đóng app giữa request có thể để job pending; mở lại sẽ báo lần trước chưa hoàn tất, không tự gửi lại. Xóa job làm provenance job_id thành null, giữ card/lịch ôn và nguồn provider/mức đã duyệt.

Backup version 2 giữ đủ 9 bảng và nguyên văn passage; preview có số passage. Restore backup 1 được hỗ trợ, hai bảng mới khởi tạo rỗng. Key/configuration secure storage của máy đích không bị restore thay thế. Dữ liệu local/backup không mã hóa; lưu file riêng tư. Migration giữ dữ liệu DB1, app cũ không đọc được DB2.

## Xác minh và phần chưa có

Local: static analysis không lỗi; 41 test Flutter gồm mock request/fallback/refusal/cancel/cap, Unicode grounding, approval atomic/idempotent, conflicting senses, backup1/2, nâng DB1 giữ lịch ôn và UI mobile sửa nghĩa → lưu. Không dùng key thật, chưa xác nhận quota/model/deployment hoặc chất lượng CEFR trên dữ liệu người dùng. CI Android và Windows đã qua 41 test mỗi nền tảng và build native thành công; release v0.3.0 đã công khai. Đã kiểm đủ ba gói tải xuống, version trong Windows/APK, DLL secure storage trong ZIP và chữ ký APK khớp bản trước. Chi tiết ở tài liệu 10.

Chưa có Google dịch dự phòng cho nhập từ đơn; Google không thể thay bước trích/phân CEFR. Chưa có importer CSV/JSON/XLSX/Parquet, tự cài update, sync, cache cleanup tự động hay UI xem toàn bộ hơn 30 job. Dữ liệu passage không bị tự xóa khi quá TTL cache; có thể xóa job trong lịch sử đang hiển thị.

## Tài liệu đã đối chiếu

- [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=chat): Chat Completions response_format/json_schema và refusal.
- [Azure OpenAI Structured Outputs](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/structured-outputs): API v1, model là deployment name, api-key.
- [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage): plugin secure storage Android/Windows, yêu cầu C++ ATL trên Windows; Android automatic backup đã tắt trong manifest.
