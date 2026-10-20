# VocabApp sync Worker

Kho dữ liệu một người dùng cho đồng bộ máy tính ↔ điện thoại, chạy trên Cloudflare Workers + D1 (gói Free). Worker chỉ xác thực bằng một token, lưu bản mới nhất của từng dòng và trả các thay đổi theo thứ tự `seq`; việc gộp do app làm.

## Deploy lần đầu

```bash
cd server/sync-worker
npm install
npx wrangler login                      # mở trình duyệt, đăng nhập Cloudflare
npx wrangler d1 create vocabapp-sync    # chép database_id vào wrangler.toml
npx wrangler d1 execute vocabapp-sync --remote --file=schema.sql
openssl rand -base64 33 | tr -d '\n=+/' | cut -c1-40 > ~/.config/vocabapp/sync-token
npx wrangler secret put SYNC_TOKEN < ~/.config/vocabapp/sync-token
npx wrangler deploy                     # in ra https://vocabapp-sync.<tên>.workers.dev
```

Trong app, trên **cả hai** thiết bị: Cài đặt → Đồng bộ → nhập địa chỉ Worker và token → **Kiểm tra và lưu**. Token chỉ nằm trong secret của Worker và secure storage của thiết bị; không commit, không đưa vào backup.

Đổi token: chạy lại `wrangler secret put SYNC_TOKEN` rồi nhập token mới trên các thiết bị.

## Giao thức (v1)

Header bắt buộc: `Authorization: Bearer <token>`, `x-sync-protocol: 1`.

| Endpoint | Mô tả |
|---|---|
| `GET /v1/status` | `{seq}` — kiểm tra kết nối |
| `GET /v1/pull?after=N&device=D&limit=L` | Dòng có `seq > N` từ thiết bị khác: `{rows, cursor, more}` |
| `POST /v1/push` `{device, rows:[{t,p,d,x,c}]}` | Ghi tối đa 500 dòng/1 MB; bản có `changed_at` cũ hơn bị bỏ qua |

Mỗi request dùng 1–2 câu SQL nên nằm trong giới hạn 50 truy vấn/request của gói Free.

## Khi Cloudflare hết hạn mức hoặc gặp sự cố

- **Dữ liệu không mất.** App là local-first: mọi thay đổi ghi vào SQLite trên máy trước, kèm hàng đợi `sync_outbox`. Khi Worker trả lỗi (hết hạn mức → 503 `quota`, mất mạng, 5xx), hàng đợi được giữ nguyên và gửi lại ở lần đồng bộ sau. Hạn mức D1 Free reset 00:00 UTC (7:00 sáng giờ VN).
- **Vẫn học bình thường** trên từng máy trong lúc chờ; chỉ việc chuyển dữ liệu giữa hai máy bị trễ.
- **Sao lưu file trong app** (Cài đặt → Sao lưu) vẫn hoạt động độc lập với Cloudflare: Sao lưu trên máy này → Khôi phục trên máy kia. Sau khi khôi phục, app đẩy toàn bộ thư viện lên server khi có kết nối lại.
- **Khôi phục server:** D1 có Time Travel (khôi phục về thời điểm trước, tối đa 7 ngày ở gói Free):
  `npx wrangler d1 time-travel restore vocabapp-sync --timestamp=<Unix hoặc RFC3339>` (lệnh in kèm bookmark cũ để hoàn tác)
- **Xuất bản sao server ra file SQL:** `npx wrangler d1 export vocabapp-sync --remote --output=sync-backup.sql`
- **Mất hẳn server / đổi tài khoản:** deploy Worker mới và nhập địa chỉ mới trong app. Khi gặp server mới, app tự đẩy lại toàn bộ thư viện từ máy.

## Chạy thử ở local

```bash
echo "SYNC_TOKEN=local-test-token-0123456789abcdef" > .dev.vars
npx wrangler d1 execute vocabapp-sync --local --file=schema.sql
npx wrangler dev --local --port 8787
# Ở thư mục app/:
SYNC_TEST_URL=http://127.0.0.1:8787 SYNC_TEST_TOKEN=local-test-token-0123456789abcdef \
  flutter test test/sync_test.dart
```
