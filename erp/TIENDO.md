# ERP Lab 2.0 – Nhật ký tiến độ

Cập nhật cuối mỗi phiên. Nguồn sự thật về thiết kế là `SPEC.md`.

## Bảng tiến độ

| Giai đoạn | Nội dung | Trạng thái | Ngày |
| --- | --- | --- | --- |
| P0 | Khảo sát, đặc tả `SPEC.md` | Xong, chờ giảng viên duyệt | 11/11/2026 |
| P1 | Tái cấu trúc mã, lõi sổ cái máy chủ, kiểm thử | Xong trên `erp2` + `erp-lab-dev` | 11/11/2026 |
| P2 | Cấu trúc tổ chức, vai trò mở rộng, dữ liệu gốc | Chưa | |
| P3 | Sổ cái, kỳ kế toán, tiền và ngân hàng | Chưa | |
| P4 | Mua hàng và kho nâng cao | Chưa | |
| P5 | Bán hàng nâng cao | Chưa | |
| P6 | Tài sản cố định | Chưa | |
| P7 | Sản xuất | Chưa | |
| P8 | Kế toán quản trị | Chưa | |
| P9 | Nhân sự và tiền lương | Chưa | |
| P10 | Thuế, khóa sổ, báo cáo tài chính | Chưa | |
| P11 | Phân quyền, kiểm soát, công cụ kiểm toán | Chưa | |
| P12 | Bài tập thực chiến | Chưa | |
| P13 | Kiểm thử tổng thể, phát hành | Chưa | |

## Môi trường

- Nhánh phát triển: `erp2`. Nhánh `main` (trang lớp đang dùng) chưa bị đụng tới.
- Project thử: `erp-lab-dev` (Singapore). `erp/config.js` trên nhánh `erp2` trỏ về project này và giao diện hiện nhãn "Môi trường thử".
- Project lớp học `erp-lab`: không chạy SQL nào. Đang ở trạng thái tạm dừng (Supabase tự dừng sau 7 ngày không dùng).
- Xem thử nhánh `erp2` không cần gộp vào `main`: https://raw.githack.com/tuanpd-alt/gialapPhamDinhTuan/erp2/erp/index.html
- Tài khoản giảng viên trên `erp-lab-dev`: `gv` (mật khẩu đã gửi trong phiên làm việc, không ghi ở đây).

## P0 – kết quả

- `SPEC.md`: mục tiêu, giản lược, kiến trúc, cấu trúc tổ chức, 15 vai trò, ma trận quyền và xung đột, danh mục T-code theo phân hệ, mô hình dữ liệu, hệ thống tài khoản 75 tài khoản theo Phụ lục II TT 99, bảng xác định tài khoản, 5 lưu đồ quy trình, 7 bất biến, 8 quyết định, tham số pháp lý.
- Nợ kỹ thuật và lỗ hổng phát hiện ở bản 1 (xếp theo mức nghiêm trọng):
  1. **Nghiêm trọng** – Bút toán của GR, IV, DL, BI do trình duyệt lập; gọi RPC trực tiếp có thể ghi bút toán tùy ý. Đã sửa ở P1.
  2. **Nghiêm trọng** – Trạng thái ban đầu (khóa tín dụng đơn bán, khóa thanh toán hóa đơn) do trình duyệt quyết định; gửi `status: approved` là vượt kiểm soát. Đã sửa ở P1.
  3. **Cao** – Số hiệu tài khoản 1111, 1121, 1561, 5111 là cấp 2 của Thông tư 200, không có trong Phụ lục II Thông tư 99. Đã đổi ở P1.
  4. **Cao** – Thuế suất GTGT viết cứng 10%; NĐ 174/2025/NĐ-CP đang giảm còn 8% đến 31/12/2026. Đã chuyển thành tham số SPRO, mặc định 8%.
  5. **Trung bình** – Số dư đầu kỳ viết cứng ở cả trình duyệt lẫn hàm `erp_balance`. Đã thay bằng chứng từ mở sổ OB.
  6. **Trung bình** – Dữ liệu gốc viết cứng ở trình duyệt. P1 đã đưa lên máy chủ (bảng `erp_mat`, `erp_partner`) để máy chủ kiểm soát; màn hình quản lý ở P2.
  7. **Thấp** – Mã giao diện một tệp 1.420 dòng. Đã tách ở P1.

## P1 – đã làm

- Tách `erp/index.html` thành `css/erp.css` và `js/00-data.js`, `10-core.js`, `20-logistics.js`, `30-finance.js`, `40-admin.js`, `50-actions.js`, `90-boot.js`. Thêm `erpModule({...})` để các giai đoạn sau đăng ký T-code, màn hình, biểu mẫu bằng tệp `js/mod-*.js`.
- SQL tách thành `sql/001_base.sql` (bản 1 nguyên trạng), `sql/002_ledger.sql`, `sql/003_hardening.sql`; `tools/build-setup.sh` gộp ra `setup.sql`.
- Máy chủ: bảng `erp_acct` (75 tài khoản), `erp_acct_det`, `erp_mat`, `erp_partner`, `erp_val`, `erp_je`, `erp_je_line`; hàm `erp_post` là cửa duy nhất tạo bút toán (kiểm tra cân, tài khoản tồn tại, đối tượng công nợ, mã vật tư); trigger chặn sửa/xóa bút toán đã ghi; `erp_doc_create` viết lại: bỏ mọi trường bút toán và trường tính toán từ trình duyệt, tự tính tổng tiền, thuế, kiểm tra số lượng còn mở, giá vốn bình quân, tín dụng, dung sai giá, hóa đơn trùng; `erp_doc_decide` ghi sổ phiếu chi/thu qua `erp_post`; chứng từ mở sổ OB; `erp_migrate_v1()` chuyển dữ liệu bản 1.
- Giao diện: biểu mẫu chỉ gửi dữ liệu đầu vào; trạng thái và số liệu lấy từ kết quả máy chủ; số dư đầu kỳ đọc từ chứng từ OB; hệ thống tài khoản đồng bộ từ máy chủ; SPRO thêm thuế suất GTGT; F.01 chỉ hiện tài khoản có số liệu; nhãn "Môi trường thử"; chân trang miễn trừ.
- Kiểm thử `tests/p1_ledger_test.sql`: 45/45 ca đạt trên `erp-lab-dev` (hai buổi ZCASE với số tính tay, 7 bất biến, 12 ca tấn công/ngoại lệ, phân quyền tầng cơ sở dữ liệu). Kiểm thử chuyển dữ liệu bản 1: bảng cân đối số phát sinh trùng 9/9 tài khoản. Kiểm thử khói giao diện: 32 T-code mở không lỗi.

## Quyết định đã chọn ở P1

| Mã | Quyết định | Lý do |
| --- | --- | --- |
| P1-1 | `erp_doc.data.je` vẫn được máy chủ ghi kèm như bản sao để giao diện hiển thị; nguồn sự thật là `erp_je_line` | Giữ nguyên các màn hình sổ sách đang chạy. Kiểm thử khẳng định hai nguồn trùng nhau. Màn hình đọc thẳng `erp_je_line` sẽ làm ở P3 (FAGLL03) |
| P1-2 | Nhập kho chưa có hóa đơn ghi Có 331 tạm tính (D5) | Giữ cách bản 1 đang dạy |
| P1-3 | Hóa đơn mua lệch giá vẫn ghi sổ, chỉ khóa thanh toán; KTT không "từ chối" được hóa đơn đã ghi sổ | Đúng logic MIRO/MRBR. Bản 1 cho từ chối nhưng không đảo bút toán, làm lệch sổ. Điều chỉnh hóa đơn sẽ có ở P4 |
| P1-4 | Mã JS tách bằng script thường, không ES modules (D8) | Không phải viết lại mã đang chạy |

## Giới hạn đã biết

- Chênh lệch giá ở MIRO luôn ghi vào 156 kể cả khi hàng đã bán (SPEC mục 8). Sửa ở P4.
- Thông báo lỗi trên máy chủ định dạng số có dấu phẩy (4,872,000). Chuyển sang dấu chấm ở P2.
- Màn hình thẻ kho chưa hiện chứng từ mở sổ như một dòng; tồn đầu kỳ hiện ở dòng đầu.
- Hướng dẫn ZCASE vẫn ghi "VAT 10%" theo bối cảnh cũ ở một số câu hỏi thảo luận. Viết lại ở P12.

## CẦN GIẢNG VIÊN KIỂM TRA

1. Danh mục tài khoản (SPEC mục 7) lấy từ bản trích Phụ lục II của Kế toán Lê Ánh; cần đối chiếu bản gốc Thông tư 99.
2. Máy tính, linh kiện có thuộc Phụ lục I, II loại trừ của NĐ 174/2025/NĐ-CP không (quyết định 8% hay 10% trong lab).
3. Chính sách thuế GTGT từ 01/01/2027.
4. Duyệt SPEC trước khi sang P2, nhất là 5 quyết định D1–D5.

## Câu hỏi cho giảng viên

- Có giữ quyết định D1 (thêm sản xuất lắp ráp) không?
- Có muốn thêm tùy chọn tài khoản trung gian GR/IR ở P4 để so sánh với cách hạch toán Việt Nam không?

## Đề xuất

- Neo mã băm sổ cái mỗi kỳ lên trang Sổ cái doanh nghiệp (P11) để nối bài ERP với bài blockchain.
