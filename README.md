# Giả lập tiền số

Mô phỏng lớp học về Bitcoin và Ethereum: ví, giao dịch, đào (PoW), sổ cái, sàn giao dịch, đặt cọc (PoS) và hợp đồng thông minh.

Mở trang: https://tuanpd-alt.github.io/gialapPhamDinhTuan/

Học viên đăng nhập bằng MSSV và mật khẩu do giảng viên cấp. Dữ liệu của làng trên trạm MQTT được mã hóa bằng khóa lớp; tệp `hocvien.json` chỉ chứa khóa lớp đã bọc bằng mật khẩu từng người. Giảng viên cấp, đặt lại, xóa tài khoản trong tab Giảng viên → "Tài khoản học viên", rồi tải tệp `hocvien.json` mới lên kho. Không đưa danh sách mật khẩu lên kho. Sau khi đăng nhập, học viên có thể bấm "Đổi mật khẩu" để tự đặt mật khẩu dễ nhớ: bản mật khẩu mới được ký bằng khóa riêng của tài khoản và lưu trên trạm trung chuyển; giảng viên cấp lại mật khẩu thì bản tự đổi cũ hết hiệu lực.

# Tạo lập Blockchain

Mô phỏng từng bước tạo lập một chuỗi khối: hàm băm SHA-256, cây Merkle, Proof-of-Work, nối chuỗi, thử giả mạo sổ cái và xác suất tấn công (Nakamoto, 2008).

Mở trang: https://tuanpd-alt.github.io/gialapPhamDinhTuan/tao-lap-blockchain.html

# Khóa và chữ ký

Mô phỏng từng bước: 12 từ khôi phục (BIP-39), khóa riêng, khóa công khai (secp256k1), địa chỉ ví, ký lệnh chuyển tiền (ECDSA), kiểm tra chữ ký và các cách kẻ gian tấn công.

Mở trang: https://tuanpd-alt.github.io/gialapPhamDinhTuan/khoa-va-chu-ky.html

# Luồng giao dịch

Sơ đồ so sánh từng bước luồng một giao dịch trên Bitcoin và trên chuỗi liên minh: tạo khóa, ký, phát lên mạng, hàng chờ, gom khối, đồng thuận, nối chuỗi.

Mở trang: https://tuanpd-alt.github.io/gialapPhamDinhTuan/luong-giao-dich.html

# ERP Lab HTTTKT

Mô phỏng ERP (theo luồng SAP) cho hai chu trình Mua hàng – Thanh toán và Bán hàng – Thu tiền, 8 công ty × 5 vai trò, sổ sách theo TT 99/2025.

Mở trang: https://tuanpd-alt.github.io/gialapPhamDinhTuan/erp/ — hướng dẫn cài đặt trong [erp/README.md](erp/README.md).
