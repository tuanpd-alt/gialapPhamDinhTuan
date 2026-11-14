/* Điều hướng chung của trang giả lập: Bảng tổng → Tài chính | Kế toán → Học tập | Bài tập → các bài theo thứ tự.
   Sửa danh mục bài ở biến MAP bên dưới; mọi trang và Bảng tổng dùng chung một danh mục này. */
(function () {
  'use strict';
  var script = document.currentScript;
  var BASE = new URL('./', script ? script.src : location.href);

  var MAP = [
    {
      id: 'taichinh', label: 'Tài chính', icon: '₿',
      desc: 'Tiền kỹ thuật số, chuỗi khối và tài sản số: đi từ cơ chế kỹ thuật nền tảng, qua vận hành một nền kinh tế tiền số, đến token hóa tài sản thực.',
      hoc: [
        {
          group: 'Chặng 1 · Nền tảng chuỗi khối',
          note: 'Học theo đúng thứ tự: mỗi bài dùng khái niệm của bài trước.',
          items: [
            { n: '1', t: 'Tạo lập Blockchain', href: 'tao-lap-blockchain.html',
              d: 'Chuỗi khối được dựng lên như thế nào và vì sao khó giả mạo.',
              parts: ['Hàm băm', 'Cây Merkle', 'Khối & Proof-of-Work', 'Nối chuỗi', 'Thử giả mạo'], deep: 'buoc' },
            { n: '2', t: 'Khóa và chữ ký', href: 'khoa-va-chu-ky.html',
              d: 'Ai được quyền tiêu một đồng tiền số: khóa riêng, khóa công khai, địa chỉ ví và chữ ký ECDSA.',
              parts: ['12 từ & khóa riêng', 'Khóa công khai & địa chỉ', 'Ký lệnh chuyển tiền', 'Kiểm tra chữ ký', 'Kẻ gian thử sức'], deep: 'buoc' },
            { n: '3', t: 'Luồng giao dịch', href: 'luong-giao-dich.html',
              d: 'Toàn cảnh một giao dịch đi từ ví đến khối, so sánh Bitcoin với chuỗi liên minh.',
              parts: ['Tạo khóa', 'Ký', 'Phát lên mạng', 'Hàng chờ', 'Gom khối', 'Đồng thuận', 'Nối chuỗi'] },
            { n: '4', t: 'Đào và đồng thuận', href: 'dao-va-dong-thuan.html',
              d: 'Nhiều người đào cạnh tranh cùng một khối: mạng thống nhất một sổ cái ra sao.',
              parts: ['Khối ứng viên', 'Cuộc đua PoW', 'Lan truyền & kiểm tra', 'Rẽ nhánh', 'Coinbase 100 khối'], deep: 'buoc' }
          ]
        },
        {
          group: 'Chặng 2 · Vận hành nền kinh tế tiền số',
          note: 'Bài 5 chạy trên mạng chung của lớp (đăng nhập bằng MSSV và mật khẩu giảng viên cấp); bài 6 chạy độc lập trong trình duyệt.',
          items: [
            { n: '5', t: 'Làng Tiền Số', href: 'lang-tien-so.html', login: true, app: true,
              d: 'Thực hành trên mạng chung của lớp, đi từ ví cá nhân đến hợp đồng thông minh.',
              parts: ['Ví của tôi', 'Chuyển tiền', 'Đào (PoW)', 'Sổ cái', 'Đặt cọc (PoS)', 'Sàn giao dịch', 'Hợp đồng thông minh'],
              deepIds: ['vi', 'chuyen', 'dao', 'socai', 'pos', 'san', 'hd'] },
            { n: '6', t: 'Stablecoin USDC', href: 'stablecoin-usdc.html',
              d: 'Vòng đời một đồng stablecoin: nạp USD, đúc token trên blockchain, lưu thông, dự trữ, đốt và rút USD.',
              parts: ['Các bên & ví', 'Nạp USD', 'Đối chiếu & ghi có', 'Đúc on-chain', 'Lưu thông', 'Dự trữ', 'Gửi về & đốt', 'Rút USD & đối soát'], deep: 'buoc' }
          ]
        },
        {
          group: 'Chặng 3 · Token hóa và tài sản số',
          note: 'Vận dụng chuỗi liên minh cho tài sản thực: từ một NFT đơn lẻ đến tài sản phân mảnh có giao dịch thứ cấp.',
          items: [
            { n: '7', t: 'NFT văn bằng', href: 'nft-van-bang.html',
              d: 'Số hóa bằng đại học thành NFT không chuyển nhượng và cổng xác minh cho nhà tuyển dụng.',
              parts: ['Quét văn bằng', 'Chuẩn hóa & bảo vệ dữ liệu', 'Ký số nhà trường', 'Ví sinh viên', 'Đúc NFT & chuyển giao', 'Lưu trữ hệ thống', 'Ghi lên blockchain', 'Kiểm tra độc nhất'], deep: 'buoc' },
            { n: '8', t: 'Token hóa tài sản', href: 'token-hoa-tai-san.html',
              d: 'Token hóa một sổ đỏ: SPV, NFT tài sản, phân mảnh, chào bán DvP và vòng đời token.',
              parts: ['Quét sổ đỏ', 'Thẩm định & SPV', 'Đúc NFT tài sản', 'Danh tính & tuân thủ', 'Phân mảnh token', 'Chào bán & đặt lệnh', 'Ghi lên blockchain', 'Vòng đời'], deep: 'buoc' }
          ]
        }
      ],
      bai: [
        { n: 'BT1', t: 'Phiếu bài tập: Đào và đồng thuận', href: 'dao-va-dong-thuan.html#buoc6', after: '4',
          d: '12 câu tự chấm, in được.' },
        { n: 'BT2', t: 'Phiếu bài tập: Stablecoin USDC', href: 'stablecoin-usdc.html#buoc9', after: '6',
          d: '12 câu tự chấm, in được.' },
        { n: 'BT3', t: 'Phiếu bài tập: NFT văn bằng', href: 'nft-van-bang.html#buoc9', after: '7',
          d: '12 câu tự chấm, in được.' },
        { n: 'BT4', t: 'Phiếu bài tập: Token hóa tài sản', href: 'token-hoa-tai-san.html#buoc9', after: '8',
          d: '13 câu tự chấm, in được.' },
        { n: 'KT', t: 'Bài kiểm tra tổng hợp', href: 'kiem-tra.html', login: true, final: true,
          d: '40 câu trắc nghiệm sinh riêng theo MSSV, 0,25 điểm/câu, chấm ngay khi nộp.' }
      ]
    },
    {
      id: 'ketoan', label: 'Kế toán', icon: '§',
      desc: 'Hệ thống thông tin kế toán: vận hành chu trình nghiệp vụ trên ERP, rồi xem blockchain cấp phép thay đổi việc ghi sổ và kiểm toán ra sao.',
      hoc: [
        {
          group: 'Chặng 1 · Hệ thống thông tin kế toán',
          note: 'Đăng nhập bằng MSSV và mật khẩu ERP Lab do giảng viên cấp.',
          items: [
            { n: '1', t: 'ERP Lab HTTTKT', href: 'erp/', login: true, app: true,
              d: 'Mỗi nhóm là một công ty, 5 vai trò, chạy chu trình theo luồng SAP; sổ sách theo TT 99/2025/TT-BTC.',
              parts: ['Mua hàng – Thanh toán', 'Bán hàng – Thu tiền', 'Phê duyệt & bất kiêm nhiệm', 'Sổ Nhật ký chung', 'Bảng cân đối số phát sinh'] }
          ]
        },
        {
          group: 'Chặng 2 · Blockchain trong kế toán – kiểm toán',
          note: 'Nên học trước bài 1 bên Tài chính (Tạo lập Blockchain).',
          items: [
            { n: '2', t: 'Sổ cái doanh nghiệp', href: 'doanh-nghiep.html',
              d: 'Nhiều đối tác cùng giữ một chuỗi chung: ai thấy dữ liệu gì, sai thì ghi điều chỉnh, kiểm toán viên băm lại chứng từ.',
              parts: ['Tạo giao dịch', 'Chuỗi khối chung', 'Quyền xem dữ liệu', 'Kiểm toán băm lại', 'Bút toán điều chỉnh', 'Thử sửa khối cũ'] }
          ]
        }
      ],
      bai: [
        { n: 'BT1', t: 'Tình huống thực hành ERP', href: 'erp/#ZCASE', after: '1', login: true,
          d: 'Buổi 1 Mua hàng – Thanh toán, Buổi 2 Bán hàng – Thu tiền và câu hỏi thảo luận (giao dịch ZCASE).' }
      ]
    }
  ];

  /* ---------- tiện ích ---------- */
  function abs(h) { return new URL(h, BASE); }
  function norm(p) { return p.replace(/index\.html$/, '').replace(/\/+$/, '/'); }
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
  function flat(dom) { var a = []; dom.hoc.forEach(function (g) { g.items.forEach(function (it) { a.push(it); }); }); return a; }
  function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function lsSet(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }

  /* Tìm vị trí trang hiện tại trong danh mục */
  function locate() {
    var here = norm(location.pathname), hash = location.hash || '';
    var hit = null;
    MAP.forEach(function (dom) {
      dom.bai.forEach(function (it, i) {
        var u = abs(it.href);
        if (norm(u.pathname) === here && (u.hash ? u.hash === hash : true) && !hit) hit = { dom: dom, mode: 'bai', i: i, it: it, exact: !!u.hash };
      });
    });
    if (hit && hit.exact) return hit;
    var lesson = null;
    MAP.forEach(function (dom) {
      flat(dom).forEach(function (it, i) {
        if (norm(abs(it.href).pathname) === here && !lesson) lesson = { dom: dom, mode: 'hoc', i: i, it: it };
      });
    });
    return lesson || hit;
  }

  window.SITE_MAP = MAP;
  window.SITE_NAV = { abs: abs, flat: flat, esc: esc };

  /* Bảng tổng tự dựng giao diện riêng từ MAP; không chèn thanh điều hướng */
  if (document.documentElement.hasAttribute('data-hub')) return;
  var emb = false; try { emb = window.self !== window.top; } catch (e) { emb = true; }
  if (emb) return;

  /* ---------- giao diện ---------- */
  var CSS = '' +
    '#gnav{--gn-bg:#ffffff;--gn-ink:#131a2c;--gn-mute:#5a6380;--gn-line:#dde2ee;--gn-soft:#eef0f6;--gn-acc:#1d5cf0;--gn-accs:#e3ebff;--gn-ok:#11805a;' +
    'position:relative;z-index:2147480000;background:var(--gn-bg);color:var(--gn-ink);border-bottom:1px solid var(--gn-line);' +
    'font:500 13px/1.35 "Be Vietnam Pro",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;-webkit-font-smoothing:antialiased}' +
    '@media (prefers-color-scheme:dark){:root:not([data-theme="light"]) #gnav{--gn-bg:#0d1426;--gn-ink:#e7ebf7;--gn-mute:#95a0bf;--gn-line:#243150;--gn-soft:#17213a;--gn-acc:#7aa2ff;--gn-accs:rgba(122,162,255,.16);--gn-ok:#3fcf92}}' +
    ':root[data-theme="dark"] #gnav{--gn-bg:#0d1426;--gn-ink:#e7ebf7;--gn-mute:#95a0bf;--gn-line:#243150;--gn-soft:#17213a;--gn-acc:#7aa2ff;--gn-accs:rgba(122,162,255,.16);--gn-ok:#3fcf92}' +
    '#gnav *{box-sizing:border-box}' +
    '#gnav .gn-in{max-width:1240px;margin:0 auto;padding:7px max(14px,env(safe-area-inset-left)) 0}' +
    '#gnav .gn-r1{display:flex;align-items:center;gap:8px;flex-wrap:wrap}' +
    '#gnav a{color:inherit;text-decoration:none}' +
    '#gnav .gn-home{display:inline-flex;align-items:center;gap:6px;font-weight:700;padding:5px 8px 5px 4px;border-radius:8px;white-space:nowrap}' +
    '#gnav .gn-home:hover{background:var(--gn-soft)}' +
    '#gnav .gn-home i{font-style:normal;display:inline-grid;place-items:center;width:22px;height:22px;border-radius:6px;background:var(--gn-acc);color:#fff;font-size:12px}' +
    '#gnav .gn-sep{width:1px;height:20px;background:var(--gn-line);margin:0 2px}' +
    '#gnav .gn-seg{display:inline-flex;background:var(--gn-soft);border-radius:9px;padding:2px;gap:2px}' +
    '#gnav .gn-seg button{border:0;background:none;color:var(--gn-mute);font:inherit;font-weight:600;padding:5px 12px;border-radius:7px;cursor:pointer;white-space:nowrap}' +
    '#gnav .gn-seg button[aria-pressed="true"]{background:var(--gn-bg);color:var(--gn-ink);box-shadow:0 1px 2px rgba(0,0,0,.12)}' +
    '#gnav .gn-seg.gn-mode button[aria-pressed="true"]{color:var(--gn-acc)}' +
    '#gnav .gn-sp{flex:1}' +
    '#gnav .gn-pn{display:inline-flex;gap:4px}' +
    '#gnav .gn-pn a{border:1px solid var(--gn-line);border-radius:8px;padding:4px 9px;color:var(--gn-mute);white-space:nowrap}' +
    '#gnav .gn-pn a:hover{color:var(--gn-ink);border-color:var(--gn-mute)}' +
    '#gnav .gn-pn a[aria-disabled="true"]{opacity:.35;pointer-events:none}' +
    '#gnav .gn-r2{display:flex;gap:2px;overflow-x:auto;scrollbar-width:none;margin-top:6px;padding-bottom:0}' +
    '#gnav .gn-r2::-webkit-scrollbar{display:none}' +
    '#gnav .gn-r2 a{flex:none;display:inline-flex;align-items:center;gap:7px;padding:7px 10px 8px;color:var(--gn-mute);border-bottom:2px solid transparent;white-space:nowrap}' +
    '#gnav .gn-r2 a:hover{color:var(--gn-ink)}' +
    '#gnav .gn-r2 a[aria-current="page"]{color:var(--gn-ink);border-bottom-color:var(--gn-acc)}' +
    '#gnav .gn-r2 b{display:inline-grid;place-items:center;min-width:20px;height:20px;padding:0 5px;border-radius:10px;background:var(--gn-soft);color:var(--gn-mute);font-size:11px;font-weight:700}' +
    '#gnav .gn-r2 a[aria-current="page"] b{background:var(--gn-acc);color:#fff}' +
    '#gnav .gn-r2 .gn-gap{flex:none;align-self:center;color:var(--gn-line);padding:0 2px}' +
    '#gnav .gn-r2 .gn-k{font-size:11px;color:var(--gn-mute);font-weight:500}' +
    '@media (max-width:640px){#gnav .gn-home span,#gnav .gn-sep{display:none}#gnav .gn-seg button{padding:5px 9px}#gnav .gn-pn{display:none}}' +
    '@media print{#gnav,#gnfoot{display:none!important}}' +
    '#gnfoot{max-width:1240px;margin:28px auto 22px;padding:0 max(14px,env(safe-area-inset-left));font:500 13px/1.4 "Be Vietnam Pro",system-ui,sans-serif}' +
    '#gnfoot .gf{display:flex;gap:10px;flex-wrap:wrap}' +
    '#gnfoot a{flex:1 1 260px;display:block;text-decoration:none;color:inherit;border:1px solid rgba(127,137,165,.35);border-radius:12px;padding:12px 14px}' +
    '#gnfoot a:hover{border-color:rgba(127,137,165,.8)}' +
    '#gnfoot small{display:block;opacity:.65;font-size:11.5px;margin-bottom:2px}' +
    '#gnfoot .gx{text-align:right}';

  var cur = locate();
  var state = {
    dom: cur ? cur.dom.id : (lsGet('gn-dom') || 'taichinh'),
    mode: cur ? cur.mode : (lsGet('gn-mode') || 'hoc')
  };
  function D(id) { for (var i = 0; i < MAP.length; i++) if (MAP[i].id === id) return MAP[i]; return MAP[0]; }

  function itemsOf(dom, mode) { return mode === 'bai' ? dom.bai : flat(dom); }
  function isCur(it, mode) {
    return cur && cur.it === it && cur.mode === mode;
  }

  function row2() {
    var dom = D(state.dom), mode = state.mode, h = '';
    if (mode === 'hoc') {
      dom.hoc.forEach(function (g, gi) {
        if (gi) h += '<span class="gn-gap" aria-hidden="true">›</span>';
        g.items.forEach(function (it) {
          h += '<a href="' + esc(abs(it.href).href) + '"' + (isCur(it, 'hoc') ? ' aria-current="page"' : '') +
            ' title="' + esc(g.group + ' — ' + it.d) + '"><b>' + esc(it.n) + '</b>' + esc(it.t) + '</a>';
        });
      });
    } else {
      dom.bai.forEach(function (it) {
        h += '<a href="' + esc(abs(it.href).href) + '"' + (isCur(it, 'bai') ? ' aria-current="page"' : '') +
          ' title="' + esc(it.d) + '"><b>' + esc(it.n) + '</b>' + esc(it.t) +
          (it.after ? ' <span class="gn-k">· sau bài ' + esc(it.after) + '</span>' : '') + '</a>';
      });
    }
    return h;
  }

  function prevNext() {
    if (!cur) return { p: null, n: null };
    var list = itemsOf(cur.dom, cur.mode), i = list.indexOf(cur.it);
    return { p: i > 0 ? list[i - 1] : null, n: i >= 0 && i < list.length - 1 ? list[i + 1] : null };
  }

  function render() {
    var pn = prevNext();
    var segD = MAP.map(function (d) {
      return '<button type="button" data-dom="' + d.id + '" aria-pressed="' + (state.dom === d.id) + '">' + esc(d.label) + '</button>';
    }).join('');
    var segM = '<button type="button" data-mode="hoc" aria-pressed="' + (state.mode === 'hoc') + '">Học tập</button>' +
      '<button type="button" data-mode="bai" aria-pressed="' + (state.mode === 'bai') + '">Bài tập</button>';
    var pnH = cur ? '<div class="gn-pn">' +
      '<a href="' + (pn.p ? esc(abs(pn.p.href).href) : '#') + '"' + (pn.p ? ' title="' + esc(pn.p.t) + '"' : ' aria-disabled="true"') + '>‹ <span>Bài trước</span></a>' +
      '<a href="' + (pn.n ? esc(abs(pn.n.href).href) : '#') + '"' + (pn.n ? ' title="' + esc(pn.n.t) + '"' : ' aria-disabled="true"') + '><span>Bài tiếp</span> ›</a></div>' : '';
    nav.innerHTML = '<div class="gn-in"><div class="gn-r1">' +
      '<a class="gn-home" href="' + esc(BASE.href) + '" title="Về Bảng tổng"><i>⌂</i><span>Bảng tổng</span></a><span class="gn-sep"></span>' +
      '<div class="gn-seg" role="group" aria-label="Lĩnh vực">' + segD + '</div>' +
      '<div class="gn-seg gn-mode" role="group" aria-label="Học tập hoặc bài tập">' + segM + '</div>' +
      '<span class="gn-sp"></span>' + pnH + '</div>' +
      '<nav class="gn-r2" aria-label="Danh sách bài">' + row2() + '</nav></div>';
    var a = nav.querySelector('.gn-r2 [aria-current]');
    if (a && a.scrollIntoView) { var r = nav.querySelector('.gn-r2'); r.scrollLeft = a.offsetLeft - r.clientWidth / 2 + a.clientWidth / 2; }
  }

  function footer() {
    var old = document.getElementById('gnfoot'); if (old) old.remove();
    if (!cur || cur.it.app) return;
    var pn = prevNext(); if (!pn.p && !pn.n) return;
    var f = document.createElement('div'); f.id = 'gnfoot';
    f.innerHTML = '<div class="gf">' +
      (pn.p ? '<a href="' + esc(abs(pn.p.href).href) + '"><small>‹ Bài trước</small>' + esc(pn.p.n + ' · ' + pn.p.t) + '</a>' : '') +
      (pn.n ? '<a class="gx" href="' + esc(abs(pn.n.href).href) + '"><small>Bài tiếp theo ›</small>' + esc(pn.n.n + ' · ' + pn.n.t) + '</a>' : '') + '</div>';
    document.body.appendChild(f);
  }

  var nav = document.createElement('div');
  nav.id = 'gnav';
  nav.addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    if (b.dataset.dom) { state.dom = b.dataset.dom; lsSet('gn-dom', state.dom); }
    if (b.dataset.mode) { state.mode = b.dataset.mode; lsSet('gn-mode', state.mode); }
    render();
  });

  function refresh() {
    var c = locate();
    if (c && (!cur || c.it !== cur.it || c.mode !== cur.mode)) { cur = c; state.dom = c.dom.id; state.mode = c.mode; render(); footer(); }
  }
  /* Các trang tự đổi #buocN bằng history.replaceState: theo dõi để chuyển giữa Học tập và Bài tập */
  try {
    var rs = history.replaceState, ps = history.pushState;
    history.replaceState = function () { var r = rs.apply(this, arguments); setTimeout(refresh, 0); return r; };
    history.pushState = function () { var r = ps.apply(this, arguments); setTimeout(refresh, 0); return r; };
  } catch (e) {}
  addEventListener('hashchange', refresh);

  function mount() {
    var st = document.createElement('style'); st.textContent = CSS; document.head.appendChild(st);
    document.body.insertBefore(nav, document.body.firstChild);
    render(); footer();
  }
  if (document.body) mount(); else document.addEventListener('DOMContentLoaded', mount);
})();
