# 07 — Backlog, lộ trình và nghiệm thu

Đây là kế hoạch thực hiện tiếp theo, không phải cam kết ngày hoàn tất. Effort cần hiệu chỉnh sau M0 và theo tốc độ phát triển/thử máy thực tế.

## 1. Milestone có điều kiện ra

| Mốc | Đầu ra | Phụ thuộc | Điều kiện hoàn thành | Effort sơ bộ một dev |
|---|---|---|---|---|
| M0 — Kiểm chứng nền tảng | Flutter skeleton Windows + APK; thử SQLite, secret storage, file picker/XLSX; kiểm provider bằng dữ liệu thử khi được cấu hình | Máy Windows, Android; toolchain | Hai release build chạy trên thiết bị; chọn package; chốt support matrix | 3–5 ngày công |
| M1 — Vòng học local | Nhóm/từ/nghĩa, manual entry, review scheduler, history, màn học tối thiểu | M0 | Học máy bay, restart giữ tiến độ, đa nghĩa/nhiều nhóm đúng | 5–8 ngày công |
| M2 — Import và AI | CSV/XLSX/JSON, converter Parquet, preview/conflict; provider jobs, fallback, review; passage extraction theo mức + JSON gọn | M1 và schema v1 | Import lặp không trùng; API lỗi vẫn học; thử fallback bằng mock và smoke thật có kiểm soát | 9–15 ngày công |
| M3 — MVP hai nền tảng | Backup/restore, migration, installer/APK, update flow, UAT, tài liệu sử dụng | M2 | Cả Windows và Android qua checklist dưới; nâng bản không mất dữ liệu | 5–8 ngày công |
| M4 — Đồng bộ | Server/auth, outbox, conflicts, review event sync | Yêu cầu đa thiết bị được chốt; M3 | Học offline hai máy rồi reconnect không mất/nhân đôi event | Ước lượng sau thiết kế sync |
| M5 — Nâng chất lượng | TTS, OCR, Crow handoff, lịch ôn tốt hơn, UI/UX | Feedback pilot | Mỗi tính năng có contract/UAT riêng | Theo ưu tiên |

Tổng M0–M3 khoảng **22–36 ngày công** ở giả định một dev quen Flutter; chưa gồm thời gian học stack, chờ chứng thư ký, tài khoản, sửa lỗi OEM hoặc thay đổi scope. Đây không phải ước tính chắc chắn cho người mới làm app. Sau M0 cần cập nhật estimate. Có Windows alpha ở M1/M2; không gọi MVP hoàn chỉnh nếu Android chưa qua M3.

## 2. Backlog có thứ tự

| ID | User story / nhiệm vụ | Liên kết | Gate |
|---|---|---|---|
| B01 | Là người dùng, tôi cài được cùng app trên Windows và Android | FR13, NFR06 | M0 |
| B02 | Tôi tạo nhóm, thêm nghĩa và tìm lại từ offline | FR01/02/07 | M1 |
| B03 | Tôi học một phiên chỉ bằng lật thẻ và đánh giá, không chép tay | FR08/09 | M1 |
| B04 | Tiến độ vẫn còn khi app bị đóng đột ngột | FR09, NFR03 | M1 |
| B05 | Tôi nhập file chuẩn và biết dòng nào lỗi/trùng trước khi lưu | FR03 | M2 |
| B06 | Tôi chuyển Parquet thành file chuẩn, không mất kiểu/nghĩa | FR03 | M2 |
| B07 | Tôi cấu hình provider độc lập và kiểm tra được kết nối | FR11 | M2 |
| B08 | Tôi cho AI bổ sung nghĩa, có Google dự phòng và chỉnh lại trước học | FR04/05/06 | M2 |
| B09 | Tôi xem số đến hạn và mức nhớ mà không gửi lịch sử ra cloud | FR10 | M3 |
| B10 | Tôi backup và chuyển thư viện/tiến độ sang điện thoại | FR12 | M3 |
| B11 | Tôi cập nhật bản mới mà không mất dữ liệu | FR13, NFR07 | M3 |
| B12 | Tôi học ở cả hai máy và đồng bộ sau khi có mạng | FR14 | M4 |
| B13 | Tôi dán passage, chọn B1+ và nhận JSON từ/nghĩa với giới hạn token | FR15, UC10 | M2 |
| B14 | Tôi luyện flashcard tự do mà không đổi lịch ôn | FC10, UC-FC02 — đề xuất P1 | M5 |
| B15 | Tôi bật Việt → Anh và giữ tiến độ độc lập từng chiều | FC11, UC-FC03 — đề xuất P1 | M5 |

M2 đã bổ sung passage extraction; estimate tăng sơ bộ 2–3 ngày công, cần xác nhận lại sau spike structured output/token budget.

## 3. Bộ UAT tối thiểu

| Test | Tình huống | Mong đợi |
|---|---|---|
| U01 | Không key, tắt mạng, thêm 5 nghĩa thủ công | Học được ngay, không đòi login |
| U02 | Import file JSON/CSV mẫu | 3 entry, 4 sense; 3 sense chờ duyệt, 1 draft; chưa tự tạo thẻ học |
| U03 | Duyệt 3 sense có nghĩa trong mẫu | 3 card; `bank` có 2 card khác nghĩa |
| U04 | Import lại cùng file, thêm membership nhóm khác | Không nhân entry/sense/card, không reset due |
| U05 | Cùng sense key nhưng nghĩa khác, file có dòng sai | Preview conflict/lỗi; không thay approved content tự động |
| U06 | XLSX có công thức, JSON sai version, file vượt giới hạn | Từ chối rõ lý do trước commit và trước gọi API |
| U07 | Parquet bảng phẳng → JSON → import | Row count/nội dung/null giữ đúng; kiểu lạ báo lỗi |
| U08 | Azure lỗi tạm, OpenAI trả nghĩa hợp lệ | Kết quả chờ duyệt, ghi nguồn OpenAI và trạng thái fallback |
| U09 | Cả AI lỗi, Google thành công | Chỉ có nghĩa dịch tạm, không bịa POS/IPA |
| U10 | Cả ba lỗi hoặc hết budget | Từ nháp còn nguyên, không tạo retry vô hạn |
| U11 | Model trả JSON đúng nhưng nghĩa vô lý | Vẫn cần review; sửa/từ chối được, chưa đưa vào học |
| U12 | Bấm rating hai lần rồi kill/reopen | Một event; đúng due và hạn mức từ mới |
| U13 | Học từ trong hai nhóm, archive một nhóm | Card không nhân đôi; tiến độ còn |
| U14 | Backup Windows → restore Android | Giữ ID/nghĩa/groups/events/due; key không xuất hiện |
| U15 | Restore archive lỗi/DB schema mới không hỗ trợ | Không thay DB đang dùng |
| U16 | Update N → N+1, migration lỗi giả lập | Nâng thành công giữ dữ liệu; lỗi không làm DB hỏng |
| U17 | APK/installer tải dở hoặc checksum sai | Không chạy cài; người dùng vẫn học trên bản hiện tại |
| U18 | Font 150%, offline, file 10.000 dòng | Layout dùng được; đo mục tiêu NFR02; UI không treo |
| U19 | Refusal/cancel/API response đến muộn | Không fallback qua refusal/cancel; không duyệt/ghi đè âm thầm |
| U20 | Key giả marker trong Settings rồi export/backup/log | Không có marker trong dữ liệu xuất và artifact build |

U21–U30 cho passage extraction được định nghĩa tại [tài liệu 08](08-passage-extraction.md) và là gate của M2/M3.

U31–U40 cho flashcard được định nghĩa tại [tài liệu 11](11-flashcards.md). P0 nghiệm thu cùng vòng học; P1 chỉ nghiệm thu khi triển khai mở rộng. B03 đã bao gồm flashcard cơ bản, không tính lại effort M1 cho việc bổ sung tài liệu này; B14/B15 cần estimate riêng khi được ưu tiên.

Unit tests tập trung vào scheduler, identity/merge, trạng thái và schema; provider contract tests dùng mock cho lỗi có kiểm soát. Integration tests cho transaction/migration/restore. E2E trên release build Windows và điện thoại Android thật; emulator hỗ trợ nhưng không thay hết thử máy thật.

## 4. Rủi ro và cách giảm

| Rủi ro | Tác động | Biện pháp / người chịu trách nhiệm |
|---|---|---|
| Chưa quen mobile và native packaging | Ước lượng lệch, có UI nhưng không cài được | Dev thực hiện M0 hai nền tảng trước feature lớn |
| Plugin XLSX/Parquet không đủ mobile | Import không đáp ứng | Dev benchmark; Parquet converter là phạm vi công khai; XLSX phải qua M0 |
| Nghĩa AI sai/đa nghĩa bị gộp | Học sai nội dung | Owner duyệt; BA tách sense; QA U03/U11 |
| Retry hoặc batch làm tăng chi phí | Tốn API ngoài dự kiến | Dev giới hạn job/request; owner đặt cloud quota |
| Người dùng kỳ vọng sync ngay | Hai máy khác tiến độ | Owner chốt A05 trước M1; nếu cần, đổi roadmap |
| Update làm mất DB/signing key bị mất | Mất dữ liệu hoặc không nâng APK được | Dev backup/migration UAT; owner giữ signing key có bản sao an toàn |
| Tập trung quá nhiều vào UI | Chậm có vòng học thực dụng | Pilot M1; chỉ mở rộng UI sau feedback |

## 5. Những lựa chọn cần xác nhận khi bắt đầu build

Không chặn việc lập bộ kickoff; đang dùng giả định trong tài liệu 01:

1. Có đúng Anh → Việt là ưu tiên đầu và admin chính là bạn?
2. Có cần hai thiết bị tự đồng bộ ngay bản đầu, hay chấp nhận dùng một máy chính rồi backup/restore?
3. Máy Windows/phiên bản Android thực tế và quy mô bộ từ ban đầu?
4. Parquet qua converter Windows có đáp ứng được giai đoạn đầu hay cần chọn file trực tiếp trên điện thoại?
5. Ưu tiên Azure hay OpenAI trước; ngân sách/giới hạn API mong muốn? Chỉ cần cấu hình key cục bộ khi triển khai, không gửi key trong tài liệu/chat.

Không coi việc chưa trả lời là đã chấp thuận các giả định. M0 có thể bắt đầu bằng dữ liệu giả/provider mock; trước khi khóa scope release cần chốt A01–A06.

## 6. Definition of Done của bộ kickoff hiện tại

Có product brief, audit dự án 1, FR/NFR, use case, mô hình dữ liệu, schema + mẫu CSV/JSON, đặc tả passage và contract JSON gọn, kiến trúc, UX nền, roadmap và UAT. Nội dung không đồng nghĩa đã có source app, converter, provider adapter, APK hay installer. Các artifact đó thuộc M0–M3.
