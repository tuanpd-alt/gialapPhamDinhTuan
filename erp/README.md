# ERP Lab HTTTKT

Phòng thực hành ERP mô phỏng theo luồng giao dịch SAP cho môn Hệ thống thông tin kế toán. Hệ thống có 8 công ty, mỗi công ty 5 vai trò, chạy hai chu trình **Mua hàng – Thanh toán** và **Bán hàng – Thu tiền**. Sổ sách theo Thông tư 99/2025/TT-BTC.

- Trang cho sinh viên: https://tuanpd-alt.github.io/gialapPhamDinhTuan/erp/
- Sinh viên đăng nhập bằng **MSSV + mật khẩu do giảng viên cấp**, không cần tài khoản Claude hay Google.
- Dữ liệu chung của lớp lưu trên **Supabase** (gói miễn phí). Mọi thao tác ghi đều đi qua hàm trên máy chủ, nên phân quyền và bất kiêm nhiệm được kiểm soát thật.

## Cài đặt lần đầu (giảng viên, khoảng 10 phút)

1. **Tạo project Supabase**
   - Vào https://supabase.com, đăng nhập (có thể dùng tài khoản GitHub).
   - Chọn **New project**, đặt tên `erp-lab`, Region chọn **Southeast Asia (Singapore)**, đặt mật khẩu database rồi tạo.
2. **Tạo cơ sở dữ liệu**
   - Mở file `erp/setup.sql`. Ở **dòng cuối**, thay `DoiMatKhauNay@2026` bằng mật khẩu giảng viên của thầy/cô (ít nhất 8 ký tự).
   - Trong Supabase, vào **SQL Editor > New query**, dán toàn bộ nội dung file và bấm **Run**. Kết quả cuối cùng phải là dòng "Đã tạo/cập nhật tài khoản giảng viên gv".
3. **Kết nối trang với Supabase**
   - Trong Supabase, vào **Project Settings > API** (hoặc bấm nút **Connect**). Chép **Project URL** và **anon public key**.
   - Trên GitHub, mở `erp/config.js`, bấm biểu tượng bút chì, dán hai giá trị vào `supabaseUrl` và `supabaseAnonKey`, rồi **Commit changes**.
   - Khóa anon là khóa công khai, được phép để trong mã nguồn. Tuyệt đối **không** dán khóa `service_role`.
4. **Kiểm tra**: mở trang ERP và đăng nhập bằng tài khoản `gv` với mật khẩu vừa đặt.

## Chuẩn bị lớp

1. Vào giao dịch **SU01**, dán danh sách lớp từ Excel. Mỗi dòng gồm `MSSV`, `Họ tên` và `Nhóm` (nhóm có thể bỏ trống), rồi bấm **Tạo tài khoản**.
2. Bấm **Tải CSV** để lưu mật khẩu vừa cấp. Mật khẩu chỉ hiện một lần. Sinh viên phải đổi mật khẩu ở lần đăng nhập đầu tiên.
3. Bấm **Tự động phân công** (5 người/công ty, đủ 5 vai trò) hoặc chọn công ty và vai trò cho từng người.
4. Sau mỗi buổi, bấm **Xoay vòng vai trò** để sinh viên đổi vai trò.
5. Sinh viên quên mật khẩu: bấm **Cấp lại MK** ở dòng của sinh viên đó.

## Vai trò và giao dịch

| Vai trò | Được lập | Ghi chú |
|---|---|---|
| Thủ kho | ME51N đề nghị mua, MIGO nhập kho, VL01N xuất kho | |
| Mua hàng | ME21N đơn mua hàng | |
| Kinh doanh | VA01 đơn bán hàng | Hệ thống kiểm tra hạn mức tín dụng |
| Kế toán công nợ | MIRO hóa đơn mua, F-53 đề nghị chi, VF01 hóa đơn bán, F-28 thu tiền | |
| Kế toán trưởng | Phê duyệt: SBWP, ME54N, ME29N, MRBR, VKM3, ZFAP | Không được duyệt chứng từ do chính mình lập |

Giảng viên có thể chọn "Thao tác như" một vai trò bất kỳ để làm mẫu. Các màn hình dành riêng cho giảng viên:

- **ZOVR**: tiến độ 8 nhóm.
- **SPRO**: tham số (dung sai giá, hạn mức tự duyệt đơn mua, kiểm tra tín dụng) và xóa dữ liệu của một nhóm.

## Kiêm nhiệm và giao quyền (nhóm thiếu người)

- Trong SU01, cột **Kiêm nhiệm / giao quyền** → **Sửa**: chọn vai trò kiêm thêm, hoặc chỉ giao quyền lập (hay duyệt) từng loại chứng từ.
- **Tự động phân công** tự giao kiêm nhiệm cho nhóm dưới 5 người: ưu tiên để Kế toán trưởng không kiêm, ghép các vai trò ít xung đột nhất.
- Hệ thống cảnh báo các cặp kiêm nhiệm xung đột (ví dụ Thủ kho kiêm Kế toán) và trường hợp người duyệt duy nhất cũng lập chứng từ.
- Nhóm 1–2 người: bật **Cho phép tự duyệt khi kiêm nhiệm** trong SPRO; nhật ký ghi rõ "tự duyệt do kiêm nhiệm".
- **Xoay vòng vai trò** chuyển nguyên phần việc (cả kiêm nhiệm) của bạn kế tiếp trong nhóm.

## Lưu ý vận hành

- **Tự tạm dừng**: project Supabase miễn phí sẽ tự tạm dừng nếu không có ai dùng trong 7 ngày. Trước buổi học, vào Supabase bấm **Restore** nếu thấy project đang tạm dừng.
- **Cập nhật dữ liệu**: trang tự cập nhật khoảng 5 giây một lần. Chứng từ do bạn khác lập sẽ hiện sau vài giây.
- **Cập nhật mã**: khi có bản sửa `setup.sql`, chạy lại toàn bộ file trong SQL Editor. Dữ liệu cũ được giữ nguyên.
- **Đổi mật khẩu giảng viên**: chạy lệnh sau trong SQL Editor:
  `select erp_create_admin('gv','MatKhauMoi','Giảng viên');`

## Cấu trúc thư mục

- `index.html`: giao diện (một file, không cần build).
- `config.js`: địa chỉ và khóa công khai của Supabase.
- `setup.sql`: bảng, chính sách bảo mật và các hàm xử lý trên máy chủ.
