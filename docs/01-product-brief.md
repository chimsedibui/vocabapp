# 01 — Product brief

Ngày: 19/10/2026. Chủ sản phẩm: người dùng cá nhân. Tên làm việc: VocabApp.

## 1. Vấn đề và kết quả mong muốn

Từ vựng nằm ở nhiều nơi, mỗi nơi một cách học; chép tay mất sức và khó duy trì. Cần một nơi lưu từ, thêm nghĩa nhanh, chia nhóm và chủ động nhắc ôn những từ chưa nhớ. Người dùng thích học từ vựng trực tiếp, ít phụ thuộc ví dụ.

Luồng giá trị: **nhập từ → chuẩn bị/duyệt nghĩa → đưa vào nhóm → học → ôn lại → theo dõi mức nhớ**. AI giảm công chuẩn bị dữ liệu, không đứng giữa mỗi lần mở thẻ và không là điều kiện để học.

## 2. Người dùng và vai trò

| Vai trò | Nhu cầu | Quyền trong bản cá nhân |
|---|---|---|
| Người học | Mở app và học ngay; không phải gõ hoặc chép tay | Học, tìm từ, xem và điều chỉnh kế hoạch |
| Admin thư viện | Quản lý nhóm, từ, import, duyệt nghĩa | Toàn quyền thư viện cá nhân |
| Chủ thiết bị | Cấu hình API, backup, cập nhật app | Toàn quyền cấu hình |

Trong MVP, ba vai trò là cùng một người. “Admin” là khu vực quản lý, chưa phải hệ thống tài khoản/phân quyền nhiều người. Nếu cần người khác quản trị nội dung cho mình, phải bổ sung identity và quyền ở milestone sau.

## 3. Nhu cầu đã có từ đề bài

- Có Windows app và Android APK, không cần lên store.
- Cơ chế API tương tự dự án 1: kiểm tra lại nhà cung cấp thực tế, có dự phòng Google Translate.
- Thêm nhóm từ vào DB cá nhân bằng tay, CSV, Excel, JSON hoặc Parquet theo schema.
- Thêm passage, LLM trích từ theo mức tối thiểu (ví dụ B1+), trả JSON mặc định và tiết kiệm token.
- Học từ vựng là trung tâm; ví dụ không bắt buộc.
- App có khả năng cập nhật và mở rộng; UI/UX phát triển dần.

## 4. Giả định để bắt đầu thiết kế

| ID | Giả định đề xuất, chưa phải yêu cầu đã xác nhận | Nếu thay đổi |
|---|---|---|
| A01 | Bắt đầu bằng Anh → Việt, UI tiếng Việt | Schema vẫn lưu ngôn ngữ cho mỗi mục; mở thêm bộ ngôn ngữ sau |
| A02 | Một chủ thư viện, BYOK: tự nhập API key của mình | Phân phối cho nhiều người cần auth/backend và quản lý chi phí |
| A03 | Ưu tiên offline; chưa cần server luôn chạy | Có thể bổ sung server sync mà giữ lõi học cục bộ |
| A04 | Ban đầu Windows là thiết bị quản trị chính | Android vẫn nhập tay, JSON/CSV/XLSX; Parquet được chuyển đổi trên Windows |
| A05 | Chưa bắt buộc tự đồng bộ tiến độ giữa hai máy ở MVP | Nếu bắt buộc từ đầu, đưa sync lên trước mốc MVP và tăng phạm vi |
| A06 | 10 từ mới/ngày, phiên 20 thẻ, ôn đến hạn trước | Là mặc định điều chỉnh được, không phải công thức học tối ưu cho mọi người |

## 5. Phạm vi

**MVP hoàn chỉnh:** thư viện cá nhân; nhóm từ; một mục nghĩa rõ ràng cho mỗi thẻ; nhập tay/dán danh sách; import có preview và chống trùng; AI enrichment và trích từ passage theo mức có duyệt; fallback Google; học offline; lịch ôn; thống kê cơ bản; backup/restore gồm tiến độ; Windows installer và Android APK; kiểm tra bản mới; migration DB.

Parquet thuộc phạm vi nhập liệu nhưng ở MVP được đáp ứng bằng utility chuyển sang JSON chuẩn trên Windows. Giao diện sẽ hướng dẫn cách này rõ ràng. Đọc trực tiếp Parquet trong app là hạng mục tiếp theo, tùy kết quả thử thư viện.

**Sau MVP:** sync tự động, reverse cards Việt → Anh, phát âm/TTS, OCR, nhận từ trực tiếp từ Crow Translate, nhắc học, bộ lọc nâng cao, tinh chỉnh thuật toán ôn, import Parquet trực tiếp và UI hoàn thiện hơn.

**Chưa đặt mục tiêu:** khóa học ngữ pháp, giáo viên AI/chatbot, mạng xã hội, thi đấu, marketplace, nhận diện phát âm, iOS, web app, thu phí, multi-tenant. Không cần vector DB hoặc RAG cho luồng lõi hiện tại.

## 6. Đo thành công

Các số dưới đây là mục tiêu thử nghiệm, chưa có số đo thực tế:

- Tạo nhóm 100 từ từ file hợp lệ trong ≤ 3 phút thao tác, không tính thời gian chờ nhà cung cấp AI.
- Từ màn hình mở app đến thẻ đến hạn đầu tiên ≤ 2 thao tác sau onboarding.
- Đóng/mở lại app không mất lượt ôn đã xác nhận; học được trong chế độ máy bay.
- Pilot 14 ngày: ghi nhận số ngày học, phút học, tỷ lệ “Nhớ/Dễ” ở lần ôn kế tiếp. Người dùng tự đánh giá mức công sức so với cách cũ; không hứa mức tăng trí nhớ khi chưa thử.
- Theo dõi số từ chưa có nghĩa/đang chờ duyệt để phát hiện bước nhập liệu gây ùn tắc.

Không dùng streak hoặc tổng từ đã thêm làm đại diện duy nhất cho khả năng nhớ. Telemetry mặc định ở máy, không cần gửi dữ liệu học ra ngoài.

## 7. Flashcard — bổ sung BA v0.3

Flashcard là luồng học chính: xem từ → tự nhớ → lật nghĩa → đánh giá → ôn theo lịch; không bắt buộc gõ hoặc ví dụ. Nền Anh → Việt đã có trong alpha. Luyện tự do và Việt → Anh là đề xuất mở rộng P1, chưa tự thêm vào scope MVP. Xem [đặc tả flashcard](11-flashcards.md).
