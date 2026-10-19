# 11 — Đặc tả flashcard

Bổ sung yêu cầu ngày 19/10/2026 · Bộ tài liệu BA v0.3. Phạm vi: chi tiết hóa FR08/FR09 và luồng flashcard trên Windows/Android. Không thay thuật toán lịch ôn đã đặc tả trong tài liệu 03.

## 1. Mục tiêu và trạng thái

Người học xem một từ, tự nhớ nghĩa, rồi lật thẻ để kiểm tra. Không bắt buộc chép tay, gõ đáp án, đọc ví dụ hoặc gọi AI trong lúc học.

**Đã có trong alpha 0.1.0:** thẻ Anh → Việt, lật để hiện nghĩa, đánh giá Quên/Khó/Nhớ/Dễ, ôn theo lịch, lọc một nhóm hoặc toàn thư viện, lưu tiến độ offline, tạm dừng thẻ, phím Space và 1–4. Đây là nền flashcard hiện tại.

**Đề xuất mở rộng, chưa triển khai và chưa coi là lựa chọn đã được người dùng xác nhận:** luyện tự do không đổi lịch ôn, chọn số thẻ/xáo trộn trong chế độ này, thẻ Việt → Anh và bộ lọc nhiều nhóm. Các mở rộng không chặn bản flashcard cơ bản.

## 2. Nội dung hai mặt thẻ

| Thành phần | Mặt trước | Sau khi lật |
|---|---|---|
| Anh → Việt — mặc định | Từ/cụm từ tiếng Anh | Nghĩa tiếng Việt đã duyệt |
| Việt → Anh — mở rộng | Một nghĩa tiếng Việt đã duyệt | Từ/cụm từ tiếng Anh tương ứng |
| Thông tin phụ | Tiến độ phiên; thẻ mới/đến hạn | Từ loại/phiên âm nếu đã có; không cần gọi API để bổ sung |
| Ví dụ/câu nguồn | Ẩn mặc định | Tùy chọn mở khi cần, không bắt buộc và không tự sinh |

Một nghĩa đã duyệt tạo một thẻ cho mỗi chiều được bật. `bank` với nghĩa “ngân hàng” và “bờ sông” có hai thẻ khác nhau. Nhóm chỉ chứa membership của entry; thêm từ vào nhóm khác không tạo thêm thẻ cùng nghĩa/chiều.

Các nghĩa của cùng một từ có thể khó phân biệt từ mặt trước chỉ có từ. Thiết kế mở rộng cho phép gợi ý rất ngắn do người dùng chọn (như “tài chính”), không lộ đáp án và không bắt buộc ví dụ. Alpha hiện chưa có trường gợi ý này. Với thẻ đảo chiều, các từ đồng nghĩa có thể cùng đúng: đây vẫn là bài tự đánh giá, không chấm sai một đáp án khác bằng khớp chuỗi.

## 3. Yêu cầu flashcard

| ID | Mức | Hành vi | Trạng thái |
|---|---|---|---|
| FC01 | P0 | Tạo thẻ từ nghĩa đã duyệt, loại bản nháp/chờ duyệt | Đã có với nhập tay; nguồn file/API sẽ nối vào sau |
| FC02 | P0 | Mặc định ẩn nghĩa; chỉ hiện khi bấm Hiện nghĩa/Space | Đã có |
| FC03 | P0 | Đánh giá sau lật bằng 4 mức nhớ | Đã có |
| FC04 | P0 | Ôn theo lịch: đến hạn trước, rồi từ mới trong hạn mức ngày | Đã có |
| FC05 | P0 | Học tất cả hoặc chọn một nhóm, tối đa 20 thẻ/phiên | Đã có; số liệu Home hiện tính toàn thư viện |
| FC06 | P0 | Lưu event và lịch ôn cùng transaction; retry không nhân đôi | Đã có |
| FC07 | P0 | Đóng phiên không tính thẻ chưa đánh giá; mở lại tiếp tục từ card state | Đã có; chưa giữ chính xác thứ tự phiên bị ngắt |
| FC08 | P0 | Sửa nghĩa có lựa chọn giữ lịch/học lại; tạm dừng/tiếp tục thẻ | Đã có từ Thư viện; shortcut sửa ngay trong phiên chưa có |
| FC09 | P0 | Dùng offline trên cả hai nền tảng, không gọi API lúc lật/đánh giá | Logic đã có; Android/Windows đã build, UAT đầy đủ trên thiết bị còn phải hoàn tất |
| FC10 | P1 | Luyện tự do, xáo trộn tùy chọn, không đổi lịch/hạn mức | Đề xuất |
| FC11 | P1 | Bật thẻ Việt → Anh với lịch ôn độc lập | Đề xuất |
| FC12 | P1 | Chọn nhiều nhóm, gợi ý phân biệt nghĩa, cấu hình phiên luyện | Đề xuất |

P0 được nghiệm thu như một phần vòng học local và MVP. P1 cần ưu tiên riêng; không mặc nhiên đưa toàn bộ mở rộng vào scope alpha hoặc đổi estimate MVP.

## 4. Use case flashcard

### UC-FC01 — Ôn theo lịch (chi tiết UC06)

**Actor:** người học. **Tiền điều kiện:** có thẻ được duyệt và không bị tạm dừng.

1. Home → chọn một nhóm hoặc tất cả → Học ngay.
2. App lấy tối đa 20 thẻ; đến hạn trước, sau đó từ mới còn trong hạn mức.
3. Hiện mặt trước, ẩn nghĩa; người học tự nhớ.
4. Chọn Hiện nghĩa/Space; hiện mặt sau và bốn nút đánh giá.
5. Chọn Quên/Khó/Nhớ/Dễ; app ghi lượt ôn và lịch mới, rồi chuyển thẻ.
6. Kết thúc phiên hiển thị số lượt đã lưu. Người dùng có thể về Home hoặc mở phiên khác nếu còn thẻ.

**Ngoại lệ:** không có thẻ phù hợp → thông báo rõ, không tự lấy từ nhóm khác. Hết hạn mức từ mới → vẫn cho ôn thẻ đến hạn. Thẻ lỗi/đã thay đổi → báo tải lại phiên, không ghi đè tiến độ mới. Nhấn đánh giá liên tiếp khi đang lưu → chỉ nhận một lượt.

**Hậu điều kiện:** chỉ lượt đã xác nhận mới ảnh hưởng tiến độ. Thẻ Quên đến hạn sau 10 phút, không chèn lại ngay để làm sai lịch.

### UC-FC02 — Luyện tự do (đề xuất P1)

1. Thư viện → chọn nhóm → Luyện tự do.
2. Chọn số thẻ (đề xuất mặc định 20) và có/không xáo trộn; chỉ lấy nghĩa đã duyệt, không lấy thẻ tạm dừng mặc định.
3. Xem mặt trước, lật, tự đánh giá hoặc chuyển tiếp/bỏ qua.
4. Cuối phiên xem số thẻ đã lật và tự đánh giá của phiên luyện.

Luyện tự do không đổi `due_at`, interval, lapse, hạn mức từ mới hoặc thống kê lượt ôn theo lịch. Nếu lưu kết quả luyện thì dùng lịch sử riêng có `mode=practice`; không ghi như review event của scheduler. Không có lối tự chuyển sang ôn theo lịch giữa phiên mà không cho người dùng biết.

### UC-FC03 — Bật chiều Việt → Anh (đề xuất P1)

Người dùng chủ động bật thẻ đảo chiều cho các nghĩa đã chọn. App tạo những thẻ còn thiếu theo cặp `(sense_id, direction)`, giữ nguyên thẻ Anh → Việt và lịch cũ. Tắt chiều đảo thì suspend thẻ đó, không xóa lịch sử. Bật lại tiếp tục tiến độ đã có.

Nếu bật hai chiều, cấu hình phiên cho phép chọn một chiều hoặc cả hai; đề xuất tránh đưa hai chiều cùng một nghĩa sát nhau để không vô tình lộ đáp án. Quy tắc chọn/xen kẽ này cần được chốt và kiểm thử khi triển khai P1.

## 5. Quy tắc đánh giá và lịch ôn

Các nút là mức nhớ do người dùng tự đánh giá, không phải mức CEFR:

| Nút | Cách hiểu | Thẻ mới | Thẻ đã học, interval cũ là I ngày |
|---|---|---|---|
| Quên | Không nhớ được nghĩa trước khi lật | Ôn lại sau 10 phút | Sau 10 phút, interval lưu về 1 ngày, tăng lapse |
| Khó | Nhớ chậm/chưa chắc | Sau 1 ngày | Sau max(1, ceil(1.2 × I)) ngày |
| Nhớ | Nhớ đúng trước khi lật | Sau 1 ngày | Sau max(1, 2 × I) ngày |
| Dễ | Nhớ nhanh và chắc | Sau 4 ngày | Sau max(4, 3 × I) ngày |

Interval tối đa 365 ngày theo scheduler v1. Lật thẻ không tự tính là nhớ. Không tự xếp “đã thuộc vĩnh viễn” vì interval dài. Ngày/hạn mức dùng Asia/Ho_Chi_Minh; timestamp lưu UTC. Chi tiết chuẩn ở [tài liệu 03](03-functional-spec.md).

Mở lại một phiên không bắt đầu lại lịch ôn: thẻ vừa được đánh giá chỉ trở lại khi đủ điều kiện. Alpha dựng lại queue; lưu/khôi phục chính xác một snapshot phiên là khả năng bổ sung, không phải hành vi đã có.

## 6. Dữ liệu và nguồn tạo thẻ

**Hiện tại:** `Entry → Sense approved → Card → ReviewEvent`. Card tham chiếu nghĩa, không sao chép nội dung thành một bản độc lập dễ lệch. Sửa nghĩa cập nhật nội dung dùng cho các thẻ liên quan; tùy lựa chọn giữ/reset schedule, nhưng không xóa review event cũ.

**Khi nối import và passage:** nhập file hoặc LLM chỉ tạo nháp/đề xuất. Sau duyệt mới có thẻ. Passage B1+ lọc danh sách từ trước bước duyệt; một khi đã duyệt, flashcard dùng nghĩa lưu cục bộ. Không gửi lại passage hoặc gọi enrichment khi mở/lật thẻ. API JSON compact vẫn giữ contract hiện tại, không thêm hai mặt thẻ/nhóm/lịch ôn vào response chỉ để tạo flashcard.

**Thẻ đảo chiều về sau:** DB alpha đang UNIQUE `sense_id`, chưa lưu direction riêng. Cần migration có version để thêm `direction`, chuyển thẻ cũ sang `recognition`, thay ràng buộc bằng UNIQUE `(sense_id, direction)` và giữ nguyên card ID, due, revision, event history. Chỉ tạo card `recall` khi được bật. Không nhân bản sense để giả lập hai chiều; backup/sync phải giữ direction khi phần này được triển khai.

## 7. UX và tương tác

```text
CHỌN CÁCH HỌC
  Nhóm: Tất cả / một nhóm
  [Ôn theo lịch]                  Có trong alpha
  [Luyện tự do]                   Đề xuất P1

TRƯỚC KHI LẬT
  Thẻ 3 / 20          Từ mới / Đến hạn
                    retain
                 [Hiện nghĩa]

SAU KHI LẬT
                    retain
                   giữ lại
          [Quên] [Khó] [Nhớ] [Dễ]
```

Desktop: Space hiện nghĩa, phím 1–4 đánh giá sau khi lật; không áp dụng shortcut học khi đang nhập nội dung. Android: nút chạm có nhãn, không bắt dùng vuốt. Vuốt và animation lật là cải tiến giao diện sau, không thay ý nghĩa đánh giá.

Trong lúc lưu, khóa đánh giá và thoát phiên để tránh hành động chồng nhau. Mất mạng không ảnh hưởng học; lỗi ghi local giữ thẻ/đáp án hiện tại và cho thử lại. Nội dung dài phải cuộn được; không cắt mất nghĩa. Chữ 150%, focus, screen-reader labels và khả năng giảm animation thuộc tiêu chí kiểm thử UX; không chỉ dựa vào màu để phân biệt mức nhớ.

## 8. Nghiệm thu bổ sung

Các dòng sau là tiêu chí nghiệm thu, không có nghĩa toàn bộ đã được tự động kiểm thử:

| ID | Tình huống | Mong đợi | Phạm vi |
|---|---|---|---|
| U31 | Mở thẻ chưa lật, bấm 1–4 | Không ghi rating hoặc tự hiện nghĩa | P0 |
| U32 | Lật thẻ rồi đóng phiên trước đánh giá | Không tạo review event, không đổi due | P0 |
| U33 | Một nghĩa ở nhiều nhóm; một từ có hai nghĩa | Không nhân card vì nhóm; các nghĩa có tiến độ riêng | P0 |
| U34 | Tắt mạng và học, đóng/mở lại app | Lượt đã xác nhận và due còn nguyên | P0 |
| U35 | Bản nháp/đề xuất passage chưa duyệt | Chưa xuất hiện trong flashcard; duyệt chỉ tạo card còn thiếu | P0; kiểm nguồn API khi có integration |
| U36 | Hết hạn mức từ mới nhưng có due | Vẫn ôn được due; không tự vượt hạn mức mới | P0 |
| U37 | Luyện tự do trước một thẻ đã học | Due/event theo lịch/hạn mức trước và sau phiên không đổi | P1 |
| U38 | Bật/tắt/bật lại chiều Việt → Anh | Không đổi schedule chiều cũ; không mất lịch chiều đảo | P1 |
| U39 | Migrate DB alpha sang hỗ trợ direction | ID, nghĩa, due và toàn bộ review cũ được giữ | P1 |
| U40 | Thẻ dài, chữ 150%, thao tác bàn phím/chạm | Đọc đủ nội dung và chọn rating được, không tràn layout | P0 |

Đối chiếu tính năng đã triển khai và giới hạn thực tế tại [tài liệu 10](10-implementation-status.md). Đợt bổ sung này chỉ cập nhật tài liệu, không thay source hoặc APK.
