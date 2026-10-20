# 14 — Đồng bộ máy tính ↔ điện thoại (single-user)

Triển khai ngày 20/10/2026. Một người dùng, không tài khoản/phân quyền: một Cloudflare Worker + D1 giữ bản mới nhất của từng dòng, xác thực bằng một token. Cách deploy, giao thức và phương án khi Cloudflare hết hạn mức: [server/sync-worker/README.md](../server/sync-worker/README.md).

## Cách hoạt động

- **Local-first.** Mọi thao tác ghi SQLite trên máy trước. Trigger SQLite ghi khóa của dòng thay đổi vào `sync_outbox`; học offline không cần mạng.
- **Một lượt đồng bộ:** kéo các dòng thiết bị khác đã đẩy sau `cursor`, áp dụng trong một transaction (khóa ngoại kiểm khi commit), rồi đẩy hàng đợi theo gói ≤500 dòng/256 KB. Lỗi mạng/hết hạn mức giữ nguyên hàng đợi.
- **Gộp:** theo từng dòng, bản sửa sau cùng thắng (`changed_at`); bản chỉnh trên máy mới hơn bản server thì giữ và gửi lên. Lượt ôn không bao giờ xung đột vì mỗi lượt có ID riêng; lịch ôn của một thẻ theo lượt ôn sau cùng. Xóa (bỏ từ khỏi nhóm, xóa job passage) đi dưới dạng tombstone.
- **ID tất định.** Nhóm, từ, nghĩa, thẻ có ID UUID v5 tính từ khóa tự nhiên (`deck_key`; từ + ngôn ngữ; từ + mã nghĩa; nghĩa). Hai máy tạo cùng một từ khi offline sẽ ra cùng một dòng. DB v4 và mỗi lần khôi phục backup cũ tự chuyển ID ngẫu nhiên sang dạng này.
- **Lần đầu gặp server:** mọi dòng có sẵn được xếp hàng với thời điểm 0, nên dữ liệu đã có trên server thắng các dòng chưa sửa trên máy mới, còn chỉnh sửa thật vẫn so theo thời gian.
- **Khi nào đồng bộ:** mở app, quay lại app, 5 giây sau mỗi thao tác hoặc phiên học, mỗi 2 phút khi app mở, và nút trên thanh tiêu đề/Cài đặt.

## Không đồng bộ

Cài đặt từng máy (giới hạn từ mới/ngày, cỡ giao diện, `device_id`), API key và token. Khôi phục backup trên một máy sẽ thay thư viện trên mọi máy khi đồng bộ tiếp, vì bản khôi phục mới hơn.

## Giới hạn đã biết

- Đồng hồ hai máy lệch nhiều thì “bản sau cùng” có thể sai thứ tự; lượt ôn vẫn đủ.
- Hai máy cùng sửa một nghĩa khi offline: giữ bản sửa sau, bản kia mất (không có merge từng trường).
- Server mới hoặc đổi địa chỉ: đẩy lại toàn bộ thư viện (≈ số dòng trong DB lượt ghi D1).

## Xác minh

9 test đồng bộ với server giả cùng quy tắc với Worker: hai máy mới, lượt ôn offline hai phía, bản sửa sau thắng, tombstone, hết hạn mức giữ hàng đợi, sai token, khôi phục backup lan sang máy kia, nâng DB v3 chuyển ID cũ. Thêm 1 test chạy với Worker thật qua `wrangler dev --local` (D1 SQL thật) đã qua.
