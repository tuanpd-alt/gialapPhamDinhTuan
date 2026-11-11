# Bảng tổng

Trang chủ https://tuanpd-alt.github.io/gialapPhamDinhTuan/ là Bảng tổng, chỉ gồm hai lĩnh vực: **Tài chính** và **Kế toán**. Mỗi lĩnh vực có hai tab con **Học tập** (lộ trình theo chặng, từ đơn giản đến phức tạp) và **Bài tập**. Mọi trang con có thanh điều hướng chung ở trên cùng (Bảng tổng · Tài chính/Kế toán · Học tập/Bài tập · danh sách bài · Bài trước/Bài tiếp).

Danh mục bài nằm trong một tệp duy nhất `nav.js` (biến `MAP`). Thêm, bớt hay đổi thứ tự bài chỉ cần sửa tệp này.

- Tài chính · Học tập: (1) Tạo lập Blockchain → (2) Khóa và chữ ký → (3) Luồng giao dịch → (4) Đào và đồng thuận → (5) Làng Tiền Số → (6) NFT văn bằng → (7) Token hóa tài sản
- Tài chính · Bài tập: phiếu Đào và đồng thuận, phiếu NFT văn bằng, phiếu Token hóa tài sản, Bài kiểm tra tổng hợp
- Kế toán · Học tập: (1) ERP Lab HTTTKT → (2) Sổ cái doanh nghiệp
- Kế toán · Bài tập: Tình huống thực hành ERP (ZCASE)

# Làng Tiền Số

Mô phỏng lớp học về Bitcoin và Ethereum: ví, giao dịch, đào (PoW), sổ cái, sàn giao dịch, đặt cọc (PoS) và hợp đồng thông minh.

Mở trang: https://tuanpd-alt.github.io/gialapPhamDinhTuan/lang-tien-so.html (thêm `#vi`, `#chuyen`, `#dao`, `#socai`, `#pos`, `#san`, `#hd` để vào thẳng từng tab)

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

# Đào và đồng thuận

Mô phỏng tình huống ba người đào A, B, C cạnh tranh khối 900.001: mỗi người tự lập khối ứng viên, cuộc đua Proof-of-Work theo sức băm, lan truyền gossip và kiểm tra độc lập ở từng nút (kể cả khi có nút bị sửa phần mềm), rẽ nhánh tạm thời và quy tắc coinbase phải chờ 100 khối. Có phiếu bài tập 12 câu tự chấm và in được.

Mở trang: https://tuanpd-alt.github.io/gialapPhamDinhTuan/dao-va-dong-thuan.html (thêm `#buoc6` để vào thẳng phần bài tập)

# Token hóa tài sản

Mô phỏng token hóa một bất động sản (sổ đỏ) qua 8 bước: quét Giấy chứng nhận và đối chiếu cơ sở dữ liệu đất đai (4 tình huống: hợp lệ, bị sửa, đang thế chấp, sổ giả), thẩm định giá và lập SPV, niêm phong hồ sơ bằng cây Merkle, đúc NFT tài sản (ERC-721), thiết lập danh tính và luật tuân thủ (ERC-3643; chế độ sandbox hoặc NQ 05/2025/NQ-CP), khóa NFT và phân mảnh thành token, chào bán với thanh toán DvP, ghi khối trên chuỗi liên minh (ngưỡng 2/3), phân phối thu nhập, chuyển nhượng thứ cấp và sự kiện kê biên qua oracle. Có phiếu bài tập 13 câu tự chấm và in được.

Mở trang: https://tuanpd-alt.github.io/gialapPhamDinhTuan/token-hoa-tai-san.html (thêm `#buoc9` để vào thẳng phần bài tập)

# Bài kiểm tra

Trang làm bài kiểm tra trắc nghiệm về tài sản số, tiền mã hóa, tiền kỹ thuật số, CBDC và ngân hàng số. Học viên đăng nhập bằng MSSV và mật khẩu của Làng Tiền Số; máy sinh đề riêng theo MSSV gồm 40 câu (8 câu mỗi chủ đề, từ ngân hàng 150 câu: khái niệm, phân biệt, tình huống và case study), mỗi câu 0,25 điểm, thang 10. Nộp bài xong hiện điểm ngay kèm giải thích từng câu và điểm theo chủ đề. Bài làm được mã hóa bằng khóa công khai của giảng viên và gửi qua trạm trung chuyển; giảng viên mở khu vực "Giảng viên" để phát cấu hình đợt (mã đợt, thời gian, mở/đóng, có hiện đáp án hay không), nhận bài, điều chỉnh điểm, xuất CSV và xem ngân hàng đề. Phần pháp lý giới hạn ở Luật 71/2025/QH15, NQ 05/2025/NQ-CP, TT 165/2026/TT-BTC và QĐ 1413/QĐ-TTg. Ngân hàng đề nằm trong kiem-tra-de.js (mã hóa nhẹ).

Mở trang: https://tuanpd-alt.github.io/gialapPhamDinhTuan/kiem-tra.html

# NFT văn bằng

Mô phỏng số hóa và phát hành NFT cho bằng đại học qua 8 bước: quét văn bằng và đối chiếu sổ gốc (4 tình huống: hợp lệ, bị sửa hạng, bằng giả, đã thu hồi), chuẩn hóa dữ liệu theo mô hình Verifiable Credentials và băm có salt (kèm thử tấn công dò tìm), nhà trường ký số ECDSA P-256 thật, sinh viên tạo ví và ký chuỗi thử thách, đúc NFT không chuyển nhượng (ERC-721 + ERC-5192) thẳng vào ví sinh viên, lưu trữ bốn lớp (trường, kho theo địa chỉ nội dung, CSDL quốc gia về văn bằng, blockchain), ghi khối trên chuỗi liên minh giáo dục, kiểm tra tính độc nhất, cổng xác minh cho nhà tuyển dụng và thu hồi văn bằng. Có phiếu bài tập 12 câu tự chấm và in được. Căn cứ: Thông tư 10/2026/TT-BGDĐT.

Mở trang: https://tuanpd-alt.github.io/gialapPhamDinhTuan/nft-van-bang.html (thêm `#buoc9` để vào thẳng phần bài tập)

# ERP Lab HTTTKT

Mô phỏng ERP (theo luồng SAP) cho hai chu trình Mua hàng – Thanh toán và Bán hàng – Thu tiền, 8 công ty × 5 vai trò, sổ sách theo TT 99/2025.

Mở trang: https://tuanpd-alt.github.io/gialapPhamDinhTuan/erp/ (thêm `#ZCASE` để mở thẳng tình huống thực hành sau khi đăng nhập) — hướng dẫn cài đặt trong [erp/README.md](erp/README.md).
