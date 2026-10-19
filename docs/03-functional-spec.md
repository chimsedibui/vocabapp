# 03 — Đặc tả chức năng và use case

Phiên bản đề xuất 0.3. P0 = bắt buộc để hoàn thành MVP trên cả hai nền tảng; P1 = mở rộng sau MVP. Parquet P0 dùng utility chuyển đổi như tài liệu 04.

## 1. Danh mục yêu cầu

| ID | Mức | Yêu cầu | Điều kiện nghiệm thu chính |
|---|---|---|---|
| FR01 | P0 | Tạo/sửa/archive nhóm; thêm/bỏ từ khỏi nhóm | Bỏ khỏi một nhóm không xóa từ đang ở nhóm khác hoặc lịch ôn |
| FR02 | P0 | Nhập tay hoặc dán nhiều từ, một từ/cụm từ mỗi dòng | Lưu bản nháp ngay cả khi chưa có API hoặc nghĩa |
| FR03 | P0 | Import CSV/XLSX/JSON và Parquet qua converter | Preview số mới/trùng/lỗi; commit có chủ đích; import lại không nhân bản |
| FR04 | P0 | Azure/OpenAI bổ sung nghĩa ngắn, từ loại tùy khả năng | Kết quả vào hàng chờ duyệt, không tự ghi đè nội dung đã duyệt |
| FR05 | P0 | Dự phòng Google Cloud Translation | Chỉ đánh dấu bản dịch tạm; không bịa phiên âm/từ loại |
| FR06 | P0 | Duyệt/sửa/từ chối nội dung; duyệt hàng loạt | Chỉ nội dung đủ nghĩa và được duyệt mới tạo thẻ học |
| FR07 | P0 | Tìm kiếm từ và nghĩa; lọc nhóm/trạng thái | Tìm trong dữ liệu local, không gọi AI |
| FR08 | P0 | Học flashcard từ → nghĩa; 4 mức nhớ | Ẩn nghĩa trước khi lật; không bắt buộc gõ đáp án |
| FR09 | P0 | Lịch ôn và tiếp tục phiên | Mỗi lượt xác nhận ghi atomically; restart không nhân đôi lượt |
| FR10 | P0 | Thống kê local | Tách số nghĩa, số thẻ, lượt ôn; không đếm trùng vì nhiều nhóm |
| FR11 | P0 | Settings API, kiểm tra kết nối, giới hạn gọi | Mỗi provider có key riêng; lỗi rõ; check kết nối là thao tác chủ động |
| FR12 | P0 | Backup/restore nội dung + tiến độ | Restore bản hợp lệ tái tạo số từ và lịch ôn; không kèm API key |
| FR13 | P0 | Installer Windows/APK Android; kiểm tra update | Nâng bản giữ DB; gói sai checksum bị chặn; không tự cài giữa phiên học |
| FR14 | P1 | Sync hai chiều, phát âm, OCR, nhận từ Crow | Đặc tả bổ sung trước khi làm; không làm tăng phụ thuộc của luồng học offline |
| FR15 | P0 | Dán passage, chọn ngưỡng trình độ, LLM trả JSON tối giản | Lọc B1+ bao gồm B1–C2; validate JSON, kiểm nguồn, giới hạn tokens và duyệt trước học; xem tài liệu 08 |

## 2. Use case

### UC01 — Bắt đầu dùng app (FR11, FR08)

**Actor:** chủ thiết bị. **Trigger:** mở lần đầu. **Tiền điều kiện:** cài app thành công.

1. Chọn ngôn ngữ học/nghĩa (mặc định en/vi), giới hạn từ mới mỗi ngày.
2. Tạo thư viện local và nhóm đầu tiên; cấu hình API có thể bỏ qua.
3. Chọn nhập tay, dán danh sách hoặc import.

**Ngoại lệ:** không mạng/không key vẫn vào app được. Thư mục DB không ghi được thì báo lỗi và không tạo thư viện nửa chừng. **Kết quả:** có local profile; không yêu cầu đăng nhập.

### UC02 — Thêm từ và nhóm bằng tay (FR01, FR02, FR06)

**Actor:** admin. **Tiền điều kiện:** thư viện mở được.

1. Chọn/tạo nhóm, nhập từ/cụm từ và ngôn ngữ.
2. Nếu tự điền nghĩa, chọn “Lưu và đưa vào học”; nếu chỉ có từ, chọn “Lưu nháp” hoặc “Bổ sung nghĩa”.
3. Kiểm tra trùng; nếu từ/nghĩa đã tồn tại, đề nghị gắn vào nhóm thay vì tạo lại.
4. Hiển thị trạng thái sau lưu.

**Ngoại lệ:** từ đa nghĩa cho phép thêm `sense_key` khác; không tự gộp nghĩa mới vào nghĩa cũ. Trường bắt buộc trống thì báo ngay tại trường. **Kết quả:** bản nháp hoặc nghĩa đã duyệt, có membership nhóm.

### UC03 — Nhập file (FR03)

**Actor:** admin. **Trigger:** chọn file. **Tiền điều kiện:** file nằm trên thiết bị; converter dùng trước nếu là Parquet.

1. Đọc metadata/giới hạn và schema; với XLSX chọn sheet `vocabulary` hoặc sheet do người dùng chọn.
2. Preview: hợp lệ mới, đã có, cần xử lý xung đột, lỗi theo dòng/cột.
3. Người dùng chọn bỏ qua trùng (mặc định) hoặc cập nhật nội dung cho các dòng đã chọn; xem thay đổi trước/sau.
4. Chọn “Nhập tất cả” khi không còn lỗi, hoặc “Chỉ nhập dòng hợp lệ” sau khi thấy số bị bỏ.
5. Commit transaction với import ID; trả báo cáo; nghĩa nhập từ file chờ duyệt, có thể duyệt hàng loạt ở bước tiếp theo.

**Ngoại lệ:** schema version lạ/file lỗi/hủy trước commit → không đổi DB. Nếu transaction lỗi → rollback toàn bộ commit đó. Import lại cùng nội dung → không thêm từ/thẻ/lượt ôn mới. **Kết quả:** báo cáo số thêm/sửa/bỏ/lỗi và truy vết import.

### UC04 — Bổ sung nghĩa bằng API (FR04, FR05, FR11)

**Actor:** admin. **Tiền điều kiện:** đã chọn các mục và ít nhất một provider hợp lệ.

1. Hiển thị số từ, provider ưu tiên, chuỗi dự phòng đang bật và giới hạn request.
2. Tạo job bền vững; tra cache rồi xử lý theo từng mục với concurrency giới hạn.
3. AI trả một hoặc nhiều nghĩa đề xuất theo schema; validate độ dài, ngôn ngữ, kiểu dữ liệu.
4. Nếu nhánh AI không dùng được, chuyển provider theo chính sách tài liệu 05; Google chỉ điền nghĩa dịch, đánh dấu `translation_only`.
5. Hiển thị nội dung trong “Chờ duyệt” cùng nguồn; lưu kết quả từng mục để không làm lại cả batch khi bị gián đoạn.

**Ngoại lệ:** lỗi tất cả → giữ nguyên từ nháp, cho sửa tay/thử lại. Cancel → ngừng lập request mới; không fallback vì cancel. Nội dung không hợp lệ không đi vào thư viện học. **Kết quả:** đề xuất chưa duyệt hoặc lỗi có thể xử lý lại.

### UC05 — Duyệt nghĩa (FR06)

**Actor:** admin. **Trigger:** mở hàng chờ.

1. Xem từ, nghĩa ngắn, từ loại nếu có, nguồn và trạng thái dịch tạm.
2. Sửa/duyệt/từ chối từng nghĩa hoặc chọn nhiều dòng để duyệt.
3. Duyệt chỉ khi từ và nghĩa không trống; thao tác xác nhận mới kích hoạt thẻ.

**Ngoại lệ:** chạy AI lần nữa tạo proposal mới, không tự thay nội dung thủ công. Nếu sửa nghĩa đã học: sửa chính tả có thể giữ lịch; thay đổi nghĩa đáng kể hiển thị lựa chọn reset lịch, không tự quyết thay người học. **Kết quả:** lưu revision nội dung; lịch ôn chỉ reset khi được chọn.

### UC06 — Học và ôn (FR08, FR09)

Đặc tả flashcard chi tiết, nội dung hai mặt, trạng thái triển khai và các mở rộng P1: [tài liệu 11](11-flashcards.md).

**Actor:** người học. **Tiền điều kiện:** có thẻ active từ nghĩa đã duyệt.

1. Home cho biết đến hạn và từ mới; bắt đầu phiên từ toàn thư viện hoặc nhóm.
2. Chọn thẻ đến hạn trước, rồi thẻ mới trong giới hạn ngày; không lặp cùng thẻ vì nằm ở nhiều nhóm.
3. Hiện từ, ẩn nghĩa. Người học tự nhớ rồi bấm/chạm lật.
4. Hiện nghĩa; chọn Quên / Khó / Nhớ / Dễ.
5. Ghi review event và cập nhật schedule trong một transaction, sau đó chuyển thẻ.
6. Kết thúc/tạm dừng → hiện đã ôn, mới học, cần ôn lại; lần sau tiếp tục từ dữ liệu đã lưu.

**Ngoại lệ:** thoát trước khi đánh giá không tính lượt; bấm hai lần dùng cùng review ID nên ghi một lần; offline hoạt động bình thường. Hết thẻ hiển thị lần đến hạn tiếp, cho luyện thêm tự chọn. **Kết quả:** tiến độ tồn tại sau restart.

### UC07 — Quản trị thư viện (FR01, FR07, FR10)

Tìm từ, sửa nghĩa, gắn nhiều nhóm, archive từ hoặc nhóm. Archive nhóm chỉ loại khỏi bộ lọc nhóm, không tạm dừng thẻ ở toàn thư viện; muốn dừng học phải suspend thẻ/entry. Xóa nhóm bỏ membership; xóa entry đưa vào thùng rác, giữ lịch sử trong 30 ngày theo đề xuất. Cho khôi phục trước khi xóa vĩnh viễn. Dashboard phân biệt thẻ đến hạn, mới, đang học, đã ôn; không gọi API.

### UC08 — Backup/restore và chuyển máy (FR12)

Xuất archive có manifest version, nội dung, nhóm, lịch sử ôn, schedule, settings học; không xuất key. Restore kiểm version, checksum, quan hệ dữ liệu rồi preview. Bản đầu hỗ trợ **thay thế toàn thư viện**, tạo backup hiện tại trước khi thay; không tự merge. Lỗi giữ nguyên thư viện cũ. Chuyển Windows sang Android bằng cùng archive, chọn một thiết bị tiếp tục làm nguồn chính. Dùng hai máy độc lập rồi restore sẽ không hợp nhất tiến độ.

### UC09 — Cập nhật app (FR13)

Check bản mới → xem version/changelog → tải gói đúng nền tảng → kiểm toàn vẹn/xác thực phát hành → sao lưu DB → người dùng chọn cài. Windows dùng installer; Android mở trình cài đặt hệ thống. Từ chối/cài lỗi vẫn giữ bản và dữ liệu cũ. Mở bản mới chạy migration transaction; migration lỗi không sửa tiếp DB, cung cấp khôi phục. Không mở DB mới bằng binary cũ khi schema không tương thích.

### UC10 — Trích từ vựng từ passage (FR15)

Dán đoạn → chọn mức tối thiểu/số từ/nhóm → LLM trả JSON term/level/meaning → validate/lọc trùng → duyệt vào thư viện. Luồng, ngoại lệ và budget được đặc tả đầy đủ tại [tài liệu 08](08-passage-extraction.md). Google Translation không thay thế chức năng trích xuất/phân mức.

## 3. Quy tắc lịch ôn v1 đề xuất

Đây là baseline kỹ thuật đơn giản để pilot, không tuyên bố là thuật toán tối ưu hay FSRS. Domain `Scheduler` có version để thay thuật toán sau mà vẫn giữ lịch sử.

- Mỗi nghĩa có một card `recognition` từ → nghĩa, tiến độ độc lập. Thẻ đảo chiều chưa bật.
- Chưa học: `new`; sau đánh giá dùng bảng dưới. `I` là interval theo ngày của lần học trước, mặc định 1 nếu chưa có.
- Quên: `relearning`, due = now + 10 phút; tăng lapse. Khó: `review`, due = now + max(1, ceil(1.2 × I)) ngày. Nhớ: `review`, due = now + max(1, ceil(2 × I)) ngày. Dễ: `review`, due = now + max(4, ceil(3 × I)) ngày. Với thẻ new: Khó 1 ngày, Nhớ 1 ngày, Dễ 4 ngày. Cap 365 ngày cho v1.
- Khi Quên, interval lưu lại là 1 ngày; lượt ôn tiếp dùng giá trị này. Thẻ 10 phút không chặn người dùng thoát phiên; chờ đến due mới được ưu tiên lại.
- Lưu timestamp UTC; ngày hạn mức và thống kê dùng timezone profile (mặc định Asia/Ho_Chi_Minh). Chuyển múi giờ không thay timestamp due; thay đổi timezone ghi settings, không viết lại review cũ.
- Hạn mức từ mới chỉ tính lượt đánh giá đầu tiên của card trong ngày; ôn lại không trừ hạn mức. Phiên 20 thẻ là kích thước phiên, không xóa backlog; cho mở phiên tiếp.
- Luyện tự do không cập nhật schedule mặc định và có nhãn riêng. Không xem thao tác “lật” là nhớ.
- Khi nhiều nhóm chứa cùng card: scheduler chọn theo card ID duy nhất. Thay đổi lịch bằng thuật toán mới phải có version và migration, không bỏ history.

## 4. Yêu cầu phi chức năng

| ID | Mục tiêu để nghiệm thu | Cách đo |
|---|---|---|
| NFR01 | Học, tìm, sửa tay, xem tiến độ không cần mạng | Toàn bộ phiên trong chế độ máy bay |
| NFR02 | Với 10.000 nghĩa: mở Home < 3s, tìm p95 < 300ms, chuyển thẻ p95 < 100ms | Release build, đo 30 lần trên Windows và Android thiết bị chốt ở M0; không tính AI |
| NFR03 | Không mất review đã xác nhận, không import một phần ngoài ý muốn | Kill app sau commit; fault injection transaction |
| NFR04 | UI vẫn phản hồi khi import/API chạy | Worker/isolate; loading/cancel; thử file giới hạn |
| NFR05 | Không chứa key trong source, log, export hoặc installer/APK | Kiểm bundle/log/backup với key giả có marker |
| NFR06 | Bàn phím desktop, chạm mobile, font scale 150%, tương phản đọc được | UAT hai thiết bị, focus và screen-reader labels |
| NFR07 | Nâng bản và khôi phục giữ dữ liệu | Fixture DB bản trước; so sánh ID/count/history/due |
