# VocabApp

Bộ tài liệu BA v0.3 • 19/10/2026 • Source Flutter cho Windows/Android; bản 0.3 bổ sung API OpenAI/Azure, trích từ từ passage theo CEFR và duyệt kết quả. Import file và dịch Google còn trong roadmap.

App cá nhân để gom từ vựng vào một thư viện, chuẩn bị nghĩa bằng API hoặc nhập file, rồi học và ôn trong một luồng thống nhất trên Windows và Android. Ưu tiên học từ–nghĩa, không bắt buộc chép tay, gõ đáp án hoặc học qua câu ví dụ.

## Code ứng dụng hiện tại

Source nằm trong [app/](app/README.md): thư viện SQLite, từ/nghĩa/nhóm, dán danh sách nháp, duyệt nghĩa, tìm kiếm và flashcard có lưu lịch ôn. Xem [tiến độ triển khai](docs/10-implementation-status.md) để phân biệt chức năng đã làm với đặc tả dự kiến.

[Tải bản mới nhất](https://github.com/chimsedibui/vocabapp/releases/latest) · [CI và release](https://github.com/chimsedibui/vocabapp/actions) · [Hướng dẫn chạy source](app/README.md)

## Đọc theo thứ tự

| Tài liệu | Nội dung |
|---|---|
| [01 — Product brief](docs/01-product-brief.md) | Vấn đề, mục tiêu, phạm vi, giả định, tiêu chí thành công |
| [02 — Đối chiếu dự án 1](docs/02-project-1-audit.md) | API thực tế, cách update, phần nên kế thừa |
| [03 — Đặc tả và use case](docs/03-functional-spec.md) | Yêu cầu, luồng chính, ngoại lệ, tiêu chí nghiệm thu |
| [04 — Dữ liệu và import](docs/04-data-and-import.md) | Mô hình DB, CSV/XLSX/JSON/Parquet, trùng dữ liệu |
| [05 — Kiến trúc và phát hành](docs/05-architecture.md) | Flutter, offline, API fallback, Windows/Android, backup/sync |
| [06 — UX nền tảng](docs/06-ux.md) | Điều hướng, wireframe nội dung, trạng thái, nguyên tắc mở rộng |
| [07 — Backlog và nghiệm thu](docs/07-delivery-plan.md) | Milestone, phụ thuộc, UAT, rủi ro và quyết định còn mở |
| [08 — Trích từ từ passage](docs/08-passage-extraction.md) | Lọc B1+, JSON gọn, ngân sách token và duyệt kết quả |
| [09 — Môi trường phát triển](docs/09-development-environment.md) | Công cụ Windows/WSL đã cài và lệnh build hai nền tảng |
| [10 — Tiến độ triển khai](docs/10-implementation-status.md) | Chức năng đã có, kiểm thử và artifact alpha |
| [11 — Flashcard](docs/11-flashcards.md) | Hai mặt thẻ, chế độ học, lịch ôn và mở rộng chiều học |
| [13 — API và passage thực tế](docs/13-api-and-passage.md) | Cấu hình key, trích CEFR, cache, duyệt và giới hạn |
| [12 — GitHub, release và backup](docs/12-releases-and-backups.md) | CI tăng version, bộ cài, khóa beta và backup/restore |

## Định hướng đề xuất

- Một codebase Flutter/Dart cho Windows và Android, SQLite lưu cục bộ; kiểm chứng các plugin trên cả hai nền tảng trước khi chốt stack.
- Azure OpenAI/OpenAI bổ sung nghĩa; Google Cloud Translation Basic v2 là dự phòng dịch đơn giản. Không cần API để học những từ đã lưu.
- Dán passage, chọn ngưỡng CEFR (ví dụ B1 trở lên), LLM trả JSON gọn gồm từ/mức/nghĩa rồi duyệt vào nhóm.
- Nhập tay, dán danh sách, CSV, XLSX, JSON; Parquet qua công cụ chuyển đổi trên Windows trong bản đầu, chưa hứa đọc trực tiếp trên Android.
- Windows ra alpha trước; Android phải có bản APK thử ngay milestone kỹ thuật đầu tiên. Hoàn thành MVP khi cả hai bản qua nghiệm thu.
- Bản đầu dùng một thiết bị chính và backup/restore để chuyển dữ liệu. Đồng bộ tự động hai chiều là milestone riêng.
- Giữ trải nghiệm cập nhật tương tự dự án 1; phần đóng gói và updater cần viết cho stack mới.

## Hợp đồng dữ liệu đi kèm

- [JSON Schema v1](schemas/vocabulary-import.v1.schema.json)
- [Dữ liệu JSON mẫu](examples/vocabulary.v1.json)
- [Dữ liệu CSV mẫu](examples/vocabulary.v1.csv)

- [Schema JSON trích passage](schemas/passage-extraction.v1.schema.json) và [response mẫu](examples/passage-response.v1.json)

Schema và file mẫu là hợp đồng đề xuất, không phải importer đã được lập trình. Các lựa chọn chưa được chủ sản phẩm xác nhận được đánh dấu rõ trong tài liệu. Không truy cập, sao chép hoặc kiểm thử bằng API key thật trong đợt kickoff này.
