# ERP Lab 2.0 – Nhật ký tiến độ

Cập nhật cuối mỗi phiên. Nguồn sự thật về thiết kế là `SPEC.md`.

## Bảng tiến độ

| Giai đoạn | Nội dung | Trạng thái | Ngày |
| --- | --- | --- | --- |
| P0 | Khảo sát, đặc tả `SPEC.md` | Xong, giảng viên đã duyệt (D1–D8) | 11/11/2026 |
| P1 | Tái cấu trúc mã, lõi sổ cái máy chủ, kiểm thử | Xong trên `erp2` + `erp-lab-dev` | 11/11/2026 |
| P2 | Cấu trúc tổ chức, vai trò mở rộng, dữ liệu gốc | Xong trên `erp2` + `erp-lab-dev` | 11/11/2026 |
| P3 | Sổ cái, kỳ kế toán, tiền và ngân hàng | **Xong** trên `erp2` + `erp-lab-dev`: rà soát xác nhận không còn Critical/High; P1 45/45, P2 29/29, P3 84/84, P3b 18/18 | 12/11/2026 |
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

## P2 – đã làm

- SQL `sql/004_masterdata.sql`:
  - Cơ cấu tổ chức `erp_org` (nhà máy 1000, kho 1001–1003, tổ chức mua, bán, kênh 10/20, trung tâm chi phí CC100–CC700, trung tâm lợi nhuận PC10–PC30).
  - 15 vai trò `erp_role`, quyền dạng dữ liệu `erp_role_perm` (C lập, A duyệt, V xem). KT được hiểu là AP + AR.
  - 5 gói vai trò `erp_role_pack`, ma trận xung đột `erp_role_conflict` cùng hàm `erp_conflict` (KTT, KSNB xung đột mức 3 với mọi vai trò tác nghiệp).
- Dữ liệu gốc riêng từng công ty:
  - Vật tư có loại HH/NVL/TP/DV, tài khoản tồn kho tự xác định (152/155/156), ngày hiệu lực và tồn tối thiểu. Thêm 6 NVL, 2 TP, 2 DV.
  - Có 6 nhà cung cấp (thêm tài khoản ngân hàng) và 6 khách hàng.
  - Bảng giá mua `erp_price` (ME11).
- Kiểm soát thay đổi dữ liệu gốc (`erp_md_save`, `erp_md_decide`):
  - Các trường nhạy cảm (tài khoản ngân hàng, hạn thanh toán, hạn mức, khóa/mở) và việc tạo mới nhà cung cấp, khách hàng phải chờ người thứ hai có quyền ZMDA duyệt. Người yêu cầu không tự duyệt được.
  - Mọi thay đổi ghi vào `erp_md_change`.
  - Chặn trùng tên vật tư, trùng mã số thuế, sai định dạng mã số thuế.
  - Phiếu chi chụp tài khoản ngân hàng đang hiệu lực lúc duyệt.
- `erp_doc_create`:
  - Kiểm tra quyền theo bảng quyền.
  - Đơn mua chỉ nhận HH/NVL, đơn bán chỉ nhận HH/TP.
  - Không dùng được đối tượng đang khóa, chưa xác nhận hoặc chưa đến ngày hiệu lực.
  - Nhập NVL ghi Nợ 152.
- `erp_sync` trả về dữ liệu gốc (chỉ công ty của sinh viên), vai trò, quyền, gói và ma trận xung đột.
- Giao diện:
  - Thêm `js/mod-md.js` với 14 T-code: MM01/02/03, XK01/02/03, XD01/02/03, ME11, FS00, ZORG, ZMDA, ZCHG.
  - Bỏ danh mục cứng (MATS/VENDORS/CUSTS đọc từ máy chủ, danh mục cứng chỉ còn làm dự phòng).
  - ME51N chỉ cho chọn HH/NVL; VA01 chỉ cho chọn HH/TP; chỉ hiện đối tượng đã xác nhận.
  - ME21N đề xuất giá từ ME11.
  - MMBE theo 152/155/156 và đánh dấu dưới mức tồn tối thiểu.
  - Quyền giao diện đọc từ bảng quyền.
  - PFCG hiện C/A/V. SU01 có thêm "Áp gói vai trò", sơ đồ tổ chức theo phần việc và cảnh báo phân công theo AP/AR.
  - Bộ chọn "Thao tác như" có đủ 15 vai trò.
- Kiểm thử:
  - `tests/p2_md_test.sql`: 29/29 đạt.
  - Chạy lại `tests/p1_ledger_test.sql`: 45/45 đạt.
  - Kiểm thử khói giao diện (dữ liệu giả lập), 45 T-code mở không lỗi và không có lỗi JS:
    - danh sách chọn trên ME51N/VA01/ME21N lọc đúng;
    - MM01 và XK02 chỉ gửi trường thay đổi;
    - quyền từng vai trò khớp ma trận.

## P3 – đã làm

- SQL `sql/005_gl_cash.sql`:
  - Bảng: `erp_co_state` (ngày làm việc, số kiểm đếm quỹ), `erp_period_close`, `erp_period_log`, `erp_bank_preset`, `erp_bank_line`; cột `cc` (trung tâm chi phí) trên dòng bút toán.
  - `erp_post`:
    - Ngày ghi sổ là ngày làm việc của công ty.
    - Chặn kỳ đã đóng theo nhóm tài khoản (Tất cả, Kho, Phải thu, Phải trả, Tài sản, Sổ cái).
    - Tài khoản có cờ bắt buộc trung tâm chi phí phải ghi trung tâm chi phí.
    - TK 141 phải ghi người nhận tạm ứng.
  - `erp_doc_create`, `erp_doc_decide` chuyển sang 005, thêm các loại:
    - JE: FB50 bút toán tay, FBS1 trích trước tự đảo ngày đầu kỳ sau, FB08 đảo bút toán (liên kết hai chiều);
    - CJ: phiếu thu, chi tiền mặt; chi tạm ứng;
    - CNT: biên bản kiểm kê quỹ;
    - ADV, ADS: đề nghị tạm ứng và thanh toán tạm ứng.
  - Bút toán tay chặn tài khoản đối chiếu (131, 331, 15x, 141…), tài khoản không cho ghi tay và tài khoản tiền.
  - Ngân hàng:
    - Chi, thu chuyển khoản ghi qua TK 113.
    - `erp_bank_issue` phát hành sao kê theo ngày làm việc (ngân hàng hạch toán ngày kế tiếp), cộng 3 khoản cài sẵn mỗi tháng: tiền về chưa rõ 15.000.000, phí 55.000, lãi 1.250.000.
    - `erp_bank_match` ghi chứng từ BS cho từng dòng sao kê.
  - OB52 `erp_period_set` chỉ Kế toán trưởng được dùng; `erp_admin_set_state` cho giảng viên đặt ngày làm việc, số kiểm đếm quỹ và cài lại khoản sao kê.
  - Cờ `bankClear` trong SPRO; tắt thì chạy như P1.
- Giao diện `js/mod-gl.js`, 12 T-code:
  - FB50, FBS1, FB08, FB03, FAGLL03 (số dư lũy kế, lọc kỳ, đối tượng, TTCP, xuất CSV);
  - ZSO: Sổ Nhật ký chung, Sổ Cái theo mẫu, in được;
  - OB52, FBCJ (sổ quỹ), ZKQ, FF67, ZBRR (bảng đối chiếu ngân hàng, in được), ZTU.
  - F.01 tính theo khoảng kỳ.
  - Hộp duyệt FBV0. Đầu trang hiện ngày làm việc; ngày mặc định trên mọi chứng từ là ngày làm việc. SPRO có phần ngày làm việc, kiểm quỹ, sao kê.
- Kiểm thử:
  - `tests/p3_gl_test.sql` 58/58, gồm 3 kịch bản nghiệm thu: (1) đóng kỳ 11, ghi vào kỳ 11 bị chặn, đảo sang kỳ 12; (2) đối chiếu ngân hàng ra đúng 3 khoản; (3) FB50 ghi vào TK 131 bị chặn.
  - Chạy lại P1 45/45, P2 29/29: hai bộ này đặt ngày làm việc 30/11/2026 và tắt TK 113.
  - Kiểm thử khói giao diện: 58 T-code, không có lỗi JS.
- Lưu ý vận hành: áp SQL bằng `apply_migration` sẽ dừng chờ xác nhận vì có lệnh xóa trong hàm; ở P3 đã áp bằng `execute_sql`.


## P3 – rà soát độc lập lần 1 và sửa lỗi

Rà soát độc lập (prompt 4.17) phát hiện 30 vấn đề: 2 Critical, 9 High, còn lại Medium/Low. Đã sửa:

| Mã | Mức | Vấn đề | Cách sửa |
| --- | --- | --- | --- |
| RV-01, 02 | Critical | Nhập kho, hóa đơn mua, giao hàng nhận hai dòng cùng `line` → vượt số lượng, ghi công nợ hai lần | `erp_doc_create` chặn dòng trùng |
| RV-03 | High | Đổi tên, MST đối tác áp dụng ngay; tạo mới thiếu thông tin kiểm tra | `name`, `mst` thành trường nhạy cảm; nhật ký tạo mới ghi tên · MST · TK NH · hạn TT · hạn mức |
| RV-04 | High | Vẫn chi được cho NCC đã khóa | Chặn khi lập, khi duyệt và khi Thủ quỹ chi |
| RV-05 | High | Duyệt FBS1 sau khi sang kỳ mới làm chi phí lệch kỳ | Chặn duyệt nếu ngày làm việc khác tháng của chứng từ; ngày tự đảo tính lúc duyệt |
| RV-06 | High | Không có cách xử lý khoản treo 3388; đảo chứng từ sao kê không mở lại dòng | `erp_susp_clear` (Nợ 3388 / Có 131, phân bổ từng phần); FB08 đảo được chứng từ BS và mở lại dòng sao kê |
| RV-07 | High | Tiền về ghi thẳng cho khách, không gắn hóa đơn → hóa đơn vẫn "chưa thu", lập phiếu thu trùng | Tiền về chỉ gắn với hóa đơn cụ thể (`opts.bi`) hoặc treo 3388; phần còn phải thu trừ phần đã phân bổ |
| RV-08 | High | Không có rút tiền gửi, nộp tiền mặt vào ngân hàng | Thêm loại `wd` (Nợ 111/Có 112, dòng sao kê khớp sẵn) và `dep` (Nợ 113/Có 111, khớp ở FF67) |
| RV-09 | High | Phiếu thu, chi tiền mặt ghi được vào mọi TK cho phép ghi tay (4111, 211…) | Danh mục TK cho phép `erp_acc_ok` theo ngữ cảnh: phiếu chi, phiếu thu, quyết toán tạm ứng |
| RV-10 | High | Thu chuyển khoản ghi qua 113 trong khi đã có giấy báo Có | Thu chuyển khoản ghi thẳng Nợ 112; chi chuyển khoản giữ qua 113, ghi rõ là cách tài khoản trung gian kiểu SAP (CẦN GIẢNG VIÊN KIỂM TRA) |
| RV-11 | High | Thủ quỹ vừa lập phiếu vừa chi tiền; tiền mặt ghi sổ ngay khi KTT duyệt | Kế toán (TH, AP, AR) lập → KTT duyệt (trạng thái "chờ thủ quỹ") → Thủ quỹ xác nhận (`erp_cash_confirm`, quyền ZTQ) mới ghi TK 111; Thủ quỹ chỉ xem FBCJ |
| RV-12 | Medium | Tự duyệt không để lại lý do | Bắt buộc ghi lý do, nhật ký có cờ `self` |
| RV-13 | Medium | Thủ quỹ tự chi tạm ứng cho mình | Chặn |
| RV-14 | Medium | Nút "Hủy hóa đơn" trên hóa đơn đã ghi sổ | Bỏ nút |
| RV-15 | Medium | Duyệt chi chuyển khoản không trừ khoản đang chuyển | Số dư khả dụng = 112 + min(0, 113) |
| RV-20 | Medium | KTT, GD, KSNB không xem được FBCJ, ZKQ, FF67, ZTU | Thêm quyền xem |
| RV-22 | Low | Kiểm quỹ không kiểm tra kỳ đã đóng | Thêm kiểm tra |
| RV-23 | Medium | Ai đăng nhập cũng gọi được `erp_bank_refresh` | Yêu cầu quyền FF67 |
| RV-26 | Low | MST trên chứng từ in 11 chữ số | Sửa còn 10 chữ số |
| RV-28 | Low | Người dùng nhầm ngày ghi sổ FB50 là ngày lập | Ghi chú trên màn hình |
| RV-29 | Medium | Bảng kết quả kiểm thử `tst_pN` nằm ở schema public; kiểm thử chạy được trên mọi CSDL | Bảng và hàm kiểm thử chuyển sang `pg_temp`; chốt `erp_cfg.main.env = "dev"` (đã đặt trên erp-lab-dev, **không đặt trên erp-lab**) |

Hoãn sang giai đoạn sau: RV-16 (hạn mức tạm ứng theo người – P9), RV-17 (phân bổ một khoản 3388 cho nhiều khách cùng lúc – P5), RV-18 (in ủy nhiệm chi theo mẫu ngân hàng – P10), RV-19 (đối chiếu sao kê nhiều tài khoản ngân hàng – P10), RV-21 (khóa sổ quỹ cuối ngày – P11), RV-24 (lịch sử số kiểm đếm quỹ – P11), RV-25 (cảnh báo tạm ứng quá hạn – P9), RV-27 (bảng chữ số bằng chữ cho số âm – P10), RV-30 (tối ưu `erp_sync` khi nhiều sao kê – P13).

Trạng thái kiểm thử (chạy trên erp-lab-dev ngày 12/11/2026, giảng viên đã cho phép lệnh có xóa dữ liệu thử):
- Toàn bộ hàm đã áp lên erp-lab-dev; md5 thân hàm trùng tệp nguồn (11 hàm).
- `tests/p3_gl_test.sql`: 82/84 đạt ở lần chạy đầu. Hai mục RV-01, RV-02 thực ra đã chặn đúng; điều kiện kiểm tra tìm chữ "trùng" trong khi thông báo là "Dòng 1 bị lặp…". Đã sửa điều kiện thành `%bị lặp%`.
- `tests/p1_ledger_test.sql` 45/45, `tests/p2_md_test.sql` 29/29 (chạy lại sau thay đổi P3).
- Đã xóa ba bảng `tst_p1`–`tst_p3` còn sót ở schema public.
- Kiểm thử khói giao diện (dữ liệu giả): 58 T-code không lỗi; hàng chờ thủ quỹ, phân bổ 3388, rút tiền gửi, chữ ký Thủ quỹ trên phiếu, FB08 liệt kê chứng từ sao kê đều chạy đúng.
- Thu hồi quyền lập FBCJ của Thủ quỹ bằng `update` (C → V) thay vì xóa dòng.
- Ghi chú RV-13: với ADV do chính Thủ quỹ lập, chốt chặn "người lập không tự chi" bắt trước chốt "Thủ quỹ không tự chi tạm ứng cho mình"; cả hai đều chặn.


## P3 – rà soát độc lập lần 2 (12/11/2026)

Kết quả: các mục RV lần 1 đã sửa thật (RV-06 sửa một phần). Phát hiện mới:

| Mã | Mức | Vấn đề | Cách sửa | Trạng thái |
| --- | --- | --- | --- | --- |
| RV2-01 | Critical | Chốt "khoản treo đã phân bổ" so sánh với trường `id` không tồn tại → đảo được khoản 3388 đã phân bổ, xóa nợ 131 không có tiền | So theo `revOf` và loại `clr`; kiểm tra lại lúc KTT duyệt; `erp_susp_clear` chặn khi đang có đề nghị FB08 chờ duyệt | Đã sửa, đã áp |
| RV2-02 | High | Bút toán đảo bỏ mất đối tượng công nợ → không duyệt được đảo chứng từ có dòng 131 | Giữ `p`, `mat`, `q` khi dựng dòng đảo | Đã sửa, đã áp |
| RV2-03 | Medium | Rút tiền gửi chỉ kiểm tra số dư lúc duyệt | Kiểm tra lại 112 + min(0, 113) khi Thủ quỹ xác nhận | Đã sửa, đã áp |
| RV2-04 | Medium | Người duyệt kiêm Thủ quỹ tự chi tiền | Chặn `decBy` = người xác nhận (trừ giảng viên) | Đã sửa, đã áp |
| RV2-05 | Medium | Chứng từ chờ thủ quỹ không có đường trả lại | Hàm `erp_cash_return` (Thủ quỹ hoặc KTT, bắt buộc lý do, nhật ký `return`); nút Trả lại ở FBCJ | Đã sửa, đã áp |
| RV2-06 | Medium | Phân bổ 3388 vượt số dư trên sổ khi 3388 bị ghi tay | Giới hạn thêm theo số dư Có 3388 trên sổ cái | Đã sửa, đã áp |
| RV2-07 | Medium | Thứ tự bút toán chi chuyển khoản qua 113 khác cách hạch toán Việt Nam (Nợ 113/Có 112 khi chuyển, Nợ 331/Có 113 khi có báo Nợ) | Giảng viên quyết định (12/11/2026): giữ mô hình kiểu SAP, ghi chú khác biệt trên FF67, F-53 và trong bài giảng (P3-9) | Đã quyết định |
| RV2-08 | Low | Nộp tiền vẫn qua 113 khi đã tắt `bankClear` | Theo cờ cấu hình | Đã sửa, đã áp |
| RV2-09 | Low | Kiểm quỹ không chặn khi còn F-53/F-28 tiền mặt, tạm ứng chờ thủ quỹ | Mở rộng điều kiện chặn | Đã sửa, đã áp |
| RV2-10 | Low | NCC không tồn tại thì `not pa.active` = null | `if not found or not pa.active` | Đã sửa, đã áp |

- 5 hàm áp lên erp-lab-dev, md5 thân hàm khớp tệp nguồn: `erp_doc_create`, `erp_doc_decide`, `erp_cash_confirm`, `erp_susp_clear`, `erp_cash_return` (mới).
- Kiểm thử trên erp-lab-dev (12/11/2026): `tests/p3b_rv2_test.sql` 18/18; chạy lại `tests/p3_gl_test.sql` 84/84 sau khi sửa.
- Kiểm thử khói giao diện: 58 T-code không lỗi.


## P3 – rà soát xác nhận (12/11/2026)

- RV2-01 … RV2-10 (trừ RV2-07 đã quyết định ở P3-9) xác nhận đã sửa đúng; md5 5 hàm trên CSDL khớp tệp nguồn. **Không còn Critical/High → đóng P3.**
- Phát hiện còn lại:

| Mã | Mức | Vấn đề | Xử lý |
| --- | --- | --- | --- |
| RV3-01 | Medium | Biên bản kiểm quỹ chờ duyệt vẫn ghi chênh lệch cũ nếu trong lúc chờ Thủ quỹ đã thu, chi | `erp_doc_decide` chặn duyệt khi số dư 111 khác số "theo sổ" lúc lập (md5 `f398abe7…` đã áp). Ca kiểm thử trong `p3b_rv2_test.sql`: P3b 19/19 đạt (12/11/2026) |
| RV3-02 | Low | Dòng đảo FB08 chép `q` không đổi dấu; hiện vô hại vì FB08 không đảo được chứng từ có dòng tồn kho | Hoãn: xử lý khi mở FB08 cho chứng từ kho (P4) |

## Quyết định đã chọn ở P3

| Mã | Quyết định | Lý do |
| --- | --- | --- |
| P3-1 | Ngày ghi sổ do máy chủ lấy theo ngày làm việc; ngày chứng từ không được sau ngày làm việc | Mô phỏng thời gian trôi do giảng viên điều khiển; chặn ghi nghiệp vụ tương lai |
| P3-2 | Chi, thu chuyển khoản qua TK 113 đến khi khớp sao kê | Sinh viên thấy rõ chênh lệch thời điểm và khoản đang chuyển |
| P3-3 | Khớp sao kê (FF67) do Kế toán tổng hợp làm và ghi sổ ngay, không qua duyệt | Sao kê ngân hàng là chứng từ bên ngoài; Kế toán trưởng kiểm soát qua ZBRR |
| P3-4 | ~~Chi tạm ứng đã duyệt ghi sổ ngay khi Thủ quỹ chi~~ → thay bằng P3-7 | |
| P3-7 | Mọi khoản thu, chi tiền mặt (F-53, F-28 tiền mặt, FBCJ, tạm ứng, quyết toán có nộp lại/chi thêm) chỉ ghi TK 111 khi Thủ quỹ xác nhận | Tách người lập – người duyệt – người giữ tiền (RV-11) |
| P3-9 | Giữ cách tài khoản trung gian kiểu SAP cho ủy nhiệm chi (Nợ 331/Có 113 khi duyệt, Nợ 113/Có 112 khi khớp sao kê); màn hình FF67, F-53 nêu rõ khác biệt với cách hạch toán Việt Nam (Nợ 113/Có 112 khi chuyển, Nợ 331/Có 113 khi có giấy báo Nợ) | Giảng viên chọn ngày 12/11/2026: dùng làm điểm so sánh SAP – Việt Nam trong bài giảng |
| P3-8 | Thu chuyển khoản ghi thẳng 112; chi chuyển khoản, nộp tiền mặt qua 113 | Thu đã có giấy báo Có; chi và nộp tiền mô phỏng độ trễ ngân hàng (RV-10) |
| P3-5 | FBS1 tự đảo bằng chứng từ riêng ghi ngày đầu kỳ sau ngay khi duyệt | Đơn giản, có dấu vết; kỳ sau đóng thì không duyệt được |
| P3-6 | Gói vai trò cho buổi P3 nên dùng PK3 (TQ, TH, AP, AR, KTT) | PK1 không có Kế toán tổng hợp, Thủ quỹ |

## Quyết định đã chọn ở P2

| Mã | Quyết định | Lý do |
| --- | --- | --- |
| P2-1 | Giữ vai trò KT (gộp AP + AR) song song với AP, AR tách riêng | Nhóm 5 người như bản 1 vẫn chạy được; gói PK2/PK3 dạy việc tách |
| P2-2 | Trường nhạy cảm chờ duyệt, trường thường áp dụng ngay | Cân bằng giữa kiểm soát và tốc độ thực hành; vẫn có nhật ký đầy đủ |
| P2-3 | Đối tượng mới tạo ở trạng thái chờ xác nhận | Mô phỏng kiểm soát chống nhà cung cấp ma |
| P2-4 | Áp gói khi thiếu người: ghế KTT luôn là ghế chính, các ghế khác ghép vào người có điểm xung đột thấp nhất | Không bao giờ để người duyệt kiêm người lập khi tránh được |
| P2-5 | Danh mục cứng ở trình duyệt chỉ còn làm dự phòng khi chưa đồng bộ | Nguồn sự thật là máy chủ |

## Quyết định đã chọn ở P1

| Mã | Quyết định | Lý do |
| --- | --- | --- |
| P1-1 | `erp_doc.data.je` vẫn được máy chủ ghi kèm như bản sao để giao diện hiển thị; nguồn sự thật là `erp_je_line` | Giữ nguyên các màn hình sổ sách đang chạy. Kiểm thử khẳng định hai nguồn trùng nhau. Màn hình đọc thẳng `erp_je_line` sẽ làm ở P3 (FAGLL03) |
| P1-2 | Nhập kho chưa có hóa đơn ghi Có 331 tạm tính (D5) | Giữ cách bản 1 đang dạy |
| P1-3 | Hóa đơn mua lệch giá vẫn ghi sổ, chỉ khóa thanh toán; KTT không "từ chối" được hóa đơn đã ghi sổ | Đúng logic MIRO/MRBR. Bản 1 cho từ chối nhưng không đảo bút toán, làm lệch sổ. Điều chỉnh hóa đơn sẽ có ở P4 |
| P1-4 | Mã JS tách bằng script thường, không ES modules (D8) | Không phải viết lại mã đang chạy |

## Giới hạn đã biết

- Chênh lệch giá ở MIRO luôn ghi vào 156 kể cả khi hàng đã bán (SPEC mục 8). Sửa ở P4.
- Đã thêm `erp_fm` (dấu chấm phân cách nghìn) ở P2; một vài thông báo lỗi cũ của P1 vẫn dùng dấu phẩy, sẽ rà khi viết P3.
- Màn hình thẻ kho chưa hiện chứng từ mở sổ như một dòng; tồn đầu kỳ hiện ở dòng đầu.
- Hướng dẫn ZCASE vẫn ghi "VAT 10%" theo bối cảnh cũ ở một số câu hỏi thảo luận. Viết lại ở P12.

## CẦN GIẢNG VIÊN KIỂM TRA

1. Danh mục tài khoản (SPEC mục 7) lấy từ bản trích Phụ lục II của Kế toán Lê Ánh; cần đối chiếu bản gốc Thông tư 99.
2. Máy tính, linh kiện có thuộc Phụ lục I, II loại trừ của NĐ 174/2025/NĐ-CP không (quyết định 8% hay 10% trong lab).
3. Chính sách thuế GTGT từ 01/01/2027.
4. Giảng viên đã duyệt SPEC (D1–D8).
5. Danh mục vai trò, ma trận xung đột (SPEC 4.3) và danh sách trường nhạy cảm có phù hợp bài giảng kiểm soát nội bộ không.
6. Mẫu sổ S03a-DN, S03b-DN ở ZSO đang theo cách đánh số quen dùng; cần đối chiếu mẫu sổ kèm Thông tư 99/2025/TT-BTC.
7. Hạch toán phí ngân hàng vào 6427, lãi tiền gửi vào 515, tiền về chưa rõ vào 3388, thiếu quỹ vào 1381, thừa quỹ vào 3381.
8. ~~Dùng TK 113 cho ủy nhiệm chi kiểu SAP~~ → đã quyết định ở P3-9.
9. Danh mục TK cho phép trên phiếu thu, phiếu chi, quyết toán tạm ứng (`erp_acc_ok`): chi 6x, 811, 1331, 242, 1381, 1388, 3381, 3388, 334, 335, 338; thu 711, 515, 1381, 1388, 3381, 3388, 338, 344.

## Câu hỏi cho giảng viên

- Có giữ quyết định D1 (thêm sản xuất lắp ráp) không?
- Có muốn thêm tùy chọn tài khoản trung gian GR/IR ở P4 để so sánh với cách hạch toán Việt Nam không?

## Đề xuất

- Neo mã băm sổ cái mỗi kỳ lên trang Sổ cái doanh nghiệp (P11) để nối bài ERP với bài blockchain.
