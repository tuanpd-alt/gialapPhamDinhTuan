"use strict";
/* ERP Lab – Hướng dẫn, quản trị giảng viên, tính tổng trực tiếp trên biểu mẫu. */
/* ============ GUIDES ============ */
function scrPFCG(){
  const codes = Object.keys(TC).filter(k=>!TC[k].admin);
  const P=S.auth&&S.auth.perms; const ACTL={C:'lập',A:'duyệt',V:'xem'};
  const cell=(k,r)=>{ if(TC[k].r===ALL) return '<span class="muted">xem</span>';
    const acts=P?[...new Set((P[r]||[]).filter(x=>x.tc===permTc(k)).map(x=>x.a))]:(roleCan([r],k)?['C']:[]);
    return acts.map(a=>a==='V'?'<span class="muted">xem</span>':`<b style="color:var(--ok)">● ${ACTL[a]}</b>`).join(' '); };
  const later=ROLE_ORDER.filter(r=>!PFCG_COLS.includes(r)&&r!=='KT');
  return `<div class="wrap">${head('PFCG','Ma trận phân quyền','Quyền đọc từ bảng erp_role_perm trên máy chủ (C lập/thay đổi, A phê duyệt, V xem); máy chủ kiểm tra lại mọi thao tác. Ma trận thể hiện nguyên tắc bất kiêm nhiệm.')}
  <div class="tw"><table class="t matrix"><thead><tr><th>Giao dịch</th>${PFCG_COLS.map(r=>`<th><span class="dot" style="background:var(--r-${r})"></span> ${esc(ROLES[r].n)}</th>`).join('')}</tr></thead><tbody>
  ${codes.map(k=>`<tr><td><code>${k}</code> ${esc(TC[k].t)}</td>${PFCG_COLS.map(r=>`<td class="small">${cell(k,r)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>
  <p class="small muted" style="margin:0">Vai trò <b>${esc(roleName('KT'))}</b> (dùng cho nhóm 5 người như bản 1) có toàn bộ quyền của Kế toán phải trả và Kế toán phải thu. Các vai trò ${later.map(r=>esc(ROLES[r].n)).join(', ')} được mở quyền ở các giai đoạn sau.</p>
  ${pfcgCompany()}
  <div class="panel"><h2>Các xung đột đã được tách</h2><ul class="small" style="margin:0;padding-left:18px;display:flex;flex-direction:column;gap:4px">
  <li>Người đề nghị mua (Thủ kho) không tự chọn nhà cung cấp và lập đơn mua (Mua hàng).</li>
  <li>Người lập đơn mua không nhập kho; người nhập kho không ghi nhận hóa đơn; người ghi nhận hóa đơn không tự duyệt chi.</li>
  <li>Người bán hàng không xuất kho và không lập hóa đơn; người thu tiền không tự xác nhận khoản thu.</li>
  <li>Kế toán trưởng phê duyệt nhưng không lập chứng từ nghiệp vụ. Hệ thống chặn người lập tự phê duyệt chứng từ của chính mình.</li>
  <li>Lưu ý thực tế: nhóm 5 người nên Kế toán công nợ kiêm lập phiếu chi/thu; doanh nghiệp thật nên tách thêm Thủ quỹ.</li></ul></div></div>`;
}
function pfcgCompany(){
  if(!S.co) return '';
  const mem=Object.values(S.users).filter(u=>!u.is_admin&&u.co===S.co&&u.role).sort((a,b)=>ROLE_ORDER.indexOf(a.role)-ROLE_ORDER.indexOf(b.role));
  if(!mem.length) return '';
  return `<div class="panel"><h2>Phân công trong công ty ${esc(S.co)}</h2><div class="tw"><table class="t"><thead><tr><th>Thành viên</th><th>Vai trò chính</th><th>Kiêm nhiệm / được giao</th><th>Điểm cần lưu ý về kiểm soát</th></tr></thead><tbody>
  ${mem.map(u=>{const xr=userRoles(u).slice(1), g=userGrants(u), cf=userConflicts(u);return `<tr><td>${esc(u.full_name)}</td><td><span class="dot" style="background:var(--r-${u.role})"></span> ${esc(roleName(u.role))}</td><td class="small">${[...xr.map(r=>esc(ROLES[r].n)),...g.map(x=>esc(grantName(x)))].join(', ')||'<span class="muted">Không</span>'}</td><td class="small">${cf.length?cf.map(x=>esc(conflictWhy(x.a,x.b))).join('; '):'<span class="muted">—</span>'}</td></tr>`;}).join('')}</tbody></table></div>
  <p class="small muted" style="margin-bottom:0">Khi kiêm nhiệm tạo xung đột, doanh nghiệp thật thường bù bằng kiểm soát khác: kiểm kê đột xuất, đối chiếu công nợ định kỳ, người ngoài bộ phận rà soát nhật ký.</p></div>`;
}
function scrCase(){
  return `<div class="wrap">${head('ZCASE','Tình huống thực hành','Mỗi nhóm là một công ty thương mại thiết bị tin học tại Nha Trang. Tồn đầu kỳ: tiền gửi 3 tỷ, tiền mặt 200 triệu, hàng hóa '+fm(INV0)+' đồng.')}
  <div class="cols">
  <div class="panel"><h2>Buổi 1 · Mua hàng – Thanh toán</h2><ol class="small" style="margin:0;padding-left:18px;display:flex;flex-direction:column;gap:6px">
   <li><b>Thủ kho</b> (ME51N) đề nghị mua 10 laptop HH01 và 20 màn hình HH02 vì tồn dưới mức dự trữ.</li>
   <li><b>Kế toán trưởng</b> (ME54N) xem xét nhu cầu, phê duyệt hoặc từ chối có ghi lý do.</li>
   <li><b>Mua hàng</b> (ME21N) so sánh báo giá 3 nhà cung cấp, chọn NCC và lập đơn mua. Giải thích vì sao chọn.</li>
   <li><b>Kế toán trưởng</b> (ME29N) duyệt đơn mua.</li>
   <li><b>Thủ kho</b> (MIGO) nhập kho. Tình huống: NCC chỉ giao 8 laptop đợt đầu, 2 cái giao sau.</li>
   <li><b>Kế toán</b> (MIRO) nhập hóa đơn GTGT. Tình huống: NCC ghi đơn giá màn hình cao hơn đơn mua 8% → hóa đơn bị khóa.</li>
   <li><b>Kế toán trưởng</b> (MRBR) quyết định gỡ khóa hoặc hủy hóa đơn.</li>
   <li><b>Kế toán</b> (F-53) đề nghị chi; <b>Kế toán trưởng</b> (ZFAP) duyệt chi. Kiểm tra sổ FBL1N, ZNKC, F.01.</li></ol></div>
  <div class="panel"><h2>Buổi 2 · Bán hàng – Thu tiền</h2><ol class="small" style="margin:0;padding-left:18px;display:flex;flex-direction:column;gap:6px">
   <li><b>Kinh doanh</b> (VA01) nhận đơn của Biển Xanh: 5 laptop, 10 màn hình, 10 chuột.</li>
   <li>Đơn thứ hai cho Phước Hải: 6 laptop → vượt hạn mức 150 triệu, đơn bị khóa tín dụng.</li>
   <li><b>Kế toán trưởng</b> (VKM3) xem dư nợ, quyết định gỡ khóa hoặc từ chối.</li>
   <li><b>Thủ kho</b> (VL01N) xuất kho giao hàng, ghi người nhận. Thử xuất vượt tồn để thấy hệ thống chặn.</li>
   <li><b>Kế toán</b> (VF01) lập hóa đơn GTGT từ phiếu xuất.</li>
   <li><b>Kế toán</b> (F-28) ghi nhận Giấy báo Có: khách trả trước 50%; <b>Kế toán trưởng</b> (ZFAP) duyệt.</li>
   <li>Đối chiếu FBL5N, MMBE (giá vốn bình quân), ZNKC và F.01.</li></ol></div>
  </div>
  <div class="panel"><h2>Câu hỏi thảo luận</h2><ol class="small" style="margin:0;padding-left:18px;display:flex;flex-direction:column;gap:4px">
   <li>Vì sao phải đối chiếu 3 bên trước khi thanh toán? Rủi ro nào xảy ra nếu bỏ qua bước MIGO?</li>
   <li>Ở thời điểm nhập kho chưa có hóa đơn, TK 331 phản ánh giá trị gì? Chênh lệch giá khi nhận hóa đơn được xử lý ra sao?</li>
   <li>Kiểm soát tín dụng nên dựa trên dư nợ 131 hay cả đơn hàng chưa xuất hóa đơn?</li>
   <li>Vẽ lưu đồ chứng từ cho một chu trình, ghi rõ bộ phận, chứng từ, số liên và điểm kiểm soát.</li>
   <li>Sau khi xoay vòng vai trò, mỗi thành viên lặp lại chu trình ở vai trò mới.</li></ol></div></div>`;
}

/* ============ ADMIN ============ */
function scrUsers(){
  const users = Object.values(S.users).filter(u=>!u.is_admin).sort((a,b)=>String(a.username).localeCompare(String(b.username)));
  const unassigned = users.filter(u=>!u.co||!u.role).length;
  const holds = (u,d) => d.c==='KTT' ? (userRoles(u).includes('KTT')||userGrants(u).includes('AP')) : (expandRoles(userRoles(u)).includes(d.c)||d.g.every(g=>userGrants(u).includes(g)));
  const grid = COS.map(co=>DUTIES.map(d=>users.filter(u=>u.co===co&&holds(u,d))));
  const packs = (S.auth&&S.auth.packs)||[];
  const warns = COS.map(co=>coWarnings(co, users)).filter(w=>w.items.length);
  const pw = S.lastPw;
  return `<div class="wrap">${head('SU01','Sinh viên & phân quyền',users.length+' tài khoản sinh viên, '+unassigned+' chưa được phân công.',
    `<button class="btn sm pri" data-act="autoAssign">Tự động phân công</button><button class="btn sm" data-act="rotate">Xoay vòng vai trò</button>`)}
  ${packs.length?`<div class="panel"><h2>Áp gói vai trò</h2><p class="small muted" style="margin-top:0">Gán lại vai trò cho mọi thành viên đã có công ty theo một gói 5 ghế (thứ tự theo MSSV). Nhóm thiếu người: ghế Kế toán trưởng luôn là ghế chính, các ghế còn lại ghép vào người có điểm xung đột thấp nhất; nhóm thừa người: người thứ 6 trở đi giữ vai trò Giám đốc (chỉ xem).</p>
   <div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center"><select id="pk-code" aria-label="Gói vai trò">${packs.map(p=>`<option value="${esc(p.c)}">${esc(p.c)} · ${esc(p.n)}</option>`).join('')}</select>
   <select id="pk-co" aria-label="Áp cho"><option value="">Cả 8 công ty</option>${COS.map(c=>`<option>${c}</option>`).join('')}</select>
   <button class="btn sm pri" data-act="applyPack">Áp gói</button></div>
   <div class="tw" style="margin-top:10px"><table class="t"><thead><tr><th>Gói</th><th>Ghế 1</th><th>Ghế 2</th><th>Ghế 3</th><th>Ghế 4</th><th>Ghế 5</th><th>Dùng cho</th></tr></thead><tbody>
   ${packs.map(p=>`<tr><td class="mono">${esc(p.c)}</td>${(p.seats||[]).map(st=>`<td class="small">${st.map(r=>esc(roleName(r))).join(' + ')}</td>`).join('')}<td class="small">${esc(p.note||'')}</td></tr>`).join('')}</tbody></table></div></div>`:''}
  ${pw&&pw.length?`<div class="panel" style="border-color:var(--warn)"><h2>Mật khẩu vừa cấp (${pw.length})</h2>
   <p class="small" style="margin-top:0">Mật khẩu chỉ hiện <b>một lần</b>. Tải file CSV hoặc chép bảng này để phát cho sinh viên. Sinh viên sẽ phải đổi mật khẩu ở lần đăng nhập đầu.</p>
   <div style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:10px"><button class="btn sm pri" data-act="dlPw">Tải CSV</button><button class="btn sm" data-act="copyPw">Chép bảng</button><button class="btn sm" data-act="clearPw">Ẩn</button></div>
   <div class="tw"><table class="t"><thead><tr><th>MSSV</th><th>Họ tên</th><th>Mật khẩu</th></tr></thead><tbody>${pw.map(x=>`<tr><td class="mono">${esc(x.mssv)}</td><td>${esc(x.name)}</td><td class="mono">${esc(x.password)}</td></tr>`).join('')}</tbody></table></div></div>`:''}
  <form class="form panel" data-form="IMPORT"><h2 style="margin:0">Nhập danh sách lớp</h2><div class="err"></div>
   <p class="small muted" style="margin:0">Dán từ Excel, mỗi dòng một sinh viên: <code>MSSV</code> · <code>Họ tên</code> · <code>Nhóm (1–8, không bắt buộc)</code>. Cột cách nhau bằng Tab, dấu phẩy hoặc chấm phẩy. MSSV đã có sẽ được bỏ qua.</p>
   <textarea id="i-rows" rows="6" style="font-family:var(--f-mono);font-size:13px;border:1px solid var(--line);border-radius:6px;padding:8px;background:var(--surface);color:var(--fg)" placeholder="62131001	Nguyễn Văn An	1&#10;62131002	Trần Thị Bình	1"></textarea>
   <div class="form-foot"><span class="small muted" id="i-preview"></span><button class="btn pri">Tạo tài khoản</button></div></form>
  <div class="panel"><h2>Sơ đồ tổ chức 8 công ty (theo phần việc)</h2><div class="tw"><table class="t"><thead><tr><th>Công ty</th>${DUTIES.map(d=>`<th><span class="dot" style="background:var(--r-${d.c})"></span> ${esc(d.n)}</th>`).join('')}</tr></thead><tbody>
  ${COS.map((co,i)=>`<tr><td class="mono">${co}</td>${grid[i].map((us,ri)=>`<td class="small">${us.length?us.map(u=>esc(u.full_name)+(u.role!==DUTIES[ri].c?' <span class="chip c-info">'+(u.role==='KT'&&(DUTIES[ri].c==='AP'||DUTIES[ri].c==='AR')?'KT':'kiêm')+'</span>':'')).join('<br>'):'<span class="muted">trống</span>'}</td>`).join('')}</tr>`).join('')}</tbody></table></div>
  <p class="small muted" style="margin-bottom:0">Nhãn <span class="chip c-info">kiêm</span> là người giữ vai trò đó do được giao kiêm nhiệm. Ô "trống" là chưa ai làm được bước đó, nhóm sẽ tắc ở bước này.</p></div>
  ${warns.length?`<div class="panel" style="border-color:var(--warn)"><h2>Cảnh báo phân công</h2><ul class="small" style="margin:0;padding-left:18px;display:flex;flex-direction:column;gap:4px">${warns.map(w=>w.items.map(x=>`<li><b class="mono">${w.co}</b> · ${x}</li>`).join('')).join('')}</ul></div>`:''}
  ${users.length?`<div class="tw"><table class="t"><thead><tr><th>MSSV</th><th>Họ tên</th><th>Nhóm muốn</th><th>Công ty</th><th>Vai trò chính</th><th>Kiêm nhiệm / giao quyền</th><th>Đăng nhập gần nhất</th><th></th></tr></thead><tbody>
  ${users.map(u=>`<tr><td class="mono">${esc(u.username)}</td><td>${esc(u.full_name)}${u.must_change?' <span class="chip c-pending">chưa đổi MK</span>':''}</td><td>${esc(u.grp||'')}</td>
   <td><select data-chg="asgCo" data-u="${esc(u.id)}" aria-label="Công ty"><option value="">—</option>${COS.map(c=>`<option ${u.co===c?'selected':''}>${c}</option>`).join('')}</select></td>
   <td><select data-chg="asgRole" data-u="${esc(u.id)}" aria-label="Vai trò"><option value="">—</option>${ROLE_ORDER.map(x=>`<option value="${x}" ${u.role===x?'selected':''}>${esc(ROLES[x].n)}</option>`).join('')}</select></td>
   <td class="small">${extraCell(u)}</td>
   <td class="small">${u.last_login?vdt(u.last_login):'<span class="muted">chưa</span>'}</td>
   <td style="white-space:nowrap"><button class="btn sm" data-act="resetPw" data-u="${esc(u.id)}">Cấp lại MK</button> <button class="btn sm badb" data-act="delUser" data-u="${esc(u.id)}">Xóa</button></td></tr>${S.editExtra===u.id?extraEditor(u):''}`).join('')}</tbody></table></div>`
  :`<div class="tw"><div class="empty">Chưa có tài khoản sinh viên. Dán danh sách lớp vào ô phía trên để tạo.</div></div>`}</div>`;
}
function extraCell(u){
  if(!u.co||!u.role) return '<span class="muted">Phân công vai trò chính trước</span>';
  const xr=userRoles(u).slice(1), g=userGrants(u), cf=userConflicts(u);
  const tags = xr.map(r=>`<span class="chip c-info">${esc(ROLES[r].n)}</span>`).concat(g.map(x=>`<span class="chip c-approved">${esc(x==='AP'?'Phê duyệt':TYPES[x].tc)}</span>`));
  return `<div style="display:flex;flex-wrap:wrap;gap:4px;align-items:center">${tags.join('')||'<span class="muted">Không</span>'} <button class="linkbtn" data-act="editExtra" data-u="${esc(u.id)}">${S.editExtra===u.id?'Đóng':'Sửa'}</button></div>${cf.length?`<div style="color:var(--warn);margin-top:2px">⚠ ${cf.map(x=>esc(conflictWhy(x.a,x.b))).join('; ')}</div>`:''}`;
}
function extraEditor(u){
  const ex=new Set(u.extra||[]);
  return `<tr><td colspan="8" style="background:var(--surface-2)"><form class="form" data-form="EXTRA" data-u="${esc(u.id)}" style="gap:10px"><div class="err"></div>
   <div><b>Giao kiêm nhiệm cho ${esc(u.full_name)}</b> <span class="muted">(vai trò chính: ${esc(roleName(u.role))}, ${esc(u.co)})</span></div>
   <div class="grid3"><div><div class="sec-title">Kiêm cả vai trò</div><div style="display:flex;flex-direction:column;gap:4px">
   ${ROLE_ORDER.filter(r=>r!==u.role).map(r=>{const sc=conflictOf(u.role,r);return `<label><input type="checkbox" name="xr" value="${r}" ${ex.has(r)?'checked':''}> ${esc(ROLES[r].n)} ${sc>=2?`<span class="small" style="color:var(--warn)">– xung đột: ${esc(conflictWhy(u.role,r))}</span>`:''}</label>`;}).join('')}</div></div>
   <div><div class="sec-title">Hoặc chỉ giao quyền lập / duyệt từng loại chứng từ</div><div style="display:flex;flex-direction:column;gap:4px">
   ${GRANTS.map(g=>`<label><input type="checkbox" name="xg" value="T:${g}" ${ex.has('T:'+g)?'checked':''}> ${esc(grantName(g))}</label>`).join('')}</div></div></div>
   <p class="small muted" style="margin:0">Kiêm vai trò = được làm mọi giao dịch của vai trò đó. Giao quyền lẻ = chỉ được lập (hoặc duyệt) đúng loại chứng từ đã chọn. Chứng từ lập bằng quyền kiêm nhiệm vẫn ghi tên người lập và vai trò tương ứng.</p>
   <div style="display:flex;gap:8px"><button class="btn pri sm">Lưu kiêm nhiệm</button><button type="button" class="btn sm" data-act="editExtra" data-u="${esc(u.id)}">Hủy</button></div></form></td></tr>`;
}
function coWarnings(co, users){
  const mem = users.filter(u=>u.co===co&&u.role); const items=[];
  if(!mem.length) return {co,items};
  const apprs = mem.filter(u=>userRoles(u).includes('KTT')||userGrants(u).includes('AP'));
  DUTIES.forEach(d=>{ if(d.c==='KTT'){ if(!apprs.length) items.push('Chưa ai giữ vai trò <b>Kế toán trưởng</b> hoặc quyền phê duyệt. Giao kiêm nhiệm cho một thành viên.'); return; }
    const ok = mem.some(u=>expandRoles(userRoles(u)).includes(d.c)) || d.g.every(g=>mem.some(u=>userGrants(u).includes(g)));
    if(!ok) items.push(`Chưa ai làm phần việc <b>${esc(d.n)}</b> (${d.g.map(g=>TYPES[g].tc).join(', ')}). Giao kiêm nhiệm cho một thành viên.`); });
  if(apprs.length===1 && !S.cfg.selfApprove){ const a=apprs[0]; const creates = userRoles(a).some(r=>r!=='KTT'&&r!=='GD'&&r!=='KSNB') || userGrants(a).some(x=>x!=='AP');
    if(creates) items.push(`<b>${esc(a.full_name)}</b> vừa là người duyệt duy nhất vừa lập chứng từ: chứng từ người này lập sẽ không ai duyệt được. Bật "Cho phép tự duyệt khi kiêm nhiệm" trong SPRO, hoặc giao thêm quyền phê duyệt cho người khác.`); }
  mem.forEach(u=>userConflicts(u).filter(x=>x.sc>=3&&!(x.a==='KTT'||x.b==='KTT')).forEach(x=>items.push(`<b>${esc(u.full_name)}</b> kiêm ${esc(roleName(x.a))} và ${esc(roleName(x.b))}: ${esc(conflictWhy(x.a,x.b))}. Nên đổi cách giao nếu nhóm đủ người.`)));
  return {co,items};
}
function scrOverview(){
  return `<div class="wrap">${head('ZOVR','Tổng quan 8 nhóm','Theo dõi tiến độ thực hành của từng công ty. Chu trình hoàn tất được tính khi phiếu chi (P2P) hoặc phiếu thu (O2C) đã được duyệt.')}
  <div class="tw"><table class="t"><thead><tr><th>Công ty</th><th class="num">Thành viên</th>${Object.keys(TYPES).map(t=>`<th class="num">${t}</th>`).join('')}<th class="num">Chờ duyệt</th><th class="num">Bị từ chối</th><th>Sổ cân</th><th>Hoạt động gần nhất</th><th></th></tr></thead><tbody>
  ${COS.map(co=>{const c=calc(co);const dr=sum(c.lines,x=>x.j.dr||0),cr=sum(c.lines,x=>x.j.cr||0);const last=c.L.length?c.L[c.L.length-1].at:null;
   return `<tr><td class="mono">${co}</td><td class="num">${Object.values(S.users).filter(a=>a.co===co&&!a.is_admin).length}</td>${Object.keys(TYPES).map(t=>`<td class="num">${c.T[t].filter(d=>d.status!=='rejected').length||''}</td>`).join('')}<td class="num">${c.Q.apAll.length||''}</td><td class="num">${c.L.filter(d=>d.status==='rejected').length||''}</td><td>${Math.abs(dr-cr)<1?'<span class="chip c-approved">Cân</span>':'<span class="chip c-rejected">Lệch</span>'}</td><td class="small">${last?vdt(last):'—'}</td><td><button class="btn sm" data-act="viewCo" data-co="${co}">Vào xem</button></td></tr>`;}).join('')}
  </tbody></table></div>
  <p class="small muted">PR đề nghị mua · PO đơn mua · GR nhập kho · IV hóa đơn mua · PAY phiếu chi · SO đơn bán · DL xuất kho · BI hóa đơn bán · RC phiếu thu.</p></div>`;
}
function scrConfig(){
  const cf = S.cfg;
  return `<div class="wrap">${head('SPRO','Tham số hệ thống & dữ liệu','Thay đổi áp dụng ngay cho cả 8 công ty.')}
  <form class="form panel" data-form="CFG"><div class="err"></div>
   <div class="grid3"><label class="field"><span>Dung sai giá hóa đơn so với đơn mua (%)</span><input id="c-tol" type="number" min="0" max="50" step="0.5" value="${cf.tol}"></label>
   <label class="field"><span>Đơn mua tự duyệt nếu tổng ≤ (đồng, 0 = luôn phải duyệt)</span><input id="c-po" type="number" min="0" step="1000000" value="${cf.poAuto}"></label>
   <label class="field"><span>Kiểm tra hạn mức tín dụng</span><select id="c-cr"><option value="1" ${cf.credit!==false?'selected':''}>Bật</option><option value="0" ${cf.credit===false?'selected':''}>Tắt</option></select></label>
   <label class="field"><span>Thuế suất GTGT áp dụng cho hàng hóa trong lab</span><select id="c-vat">${[[0.08,'8% – giảm theo NĐ 174/2025/NĐ-CP (01/07/2025–31/12/2026)'],[0.1,'10% – thuế suất phổ thông'],[0.05,'5%'],[0,'0%']].map(([v,l])=>`<option value="${v}" ${+cf.vat===v?'selected':''}>${l}</option>`).join('')}</select></label>
   <label class="field"><span>Cho phép tự duyệt khi kiêm nhiệm (nhóm 1–2 người)</span><select id="c-self"><option value="0" ${!cf.selfApprove?'selected':''}>Không – người lập không được tự duyệt</option><option value="1" ${cf.selfApprove?'selected':''}>Có – ghi chú "tự duyệt" vào nhật ký</option></select></label></div>
   <div class="form-foot"><span></span><button class="btn pri">Lưu tham số</button></div></form>
  <div class="panel"><h2>Làm mới dữ liệu một công ty</h2><p class="small muted" style="margin-top:0">Xóa toàn bộ chứng từ của công ty được chọn để bắt đầu lại từ số dư đầu kỳ. Không thể hoàn tác.</p>
   <div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center"><select id="c-reset" aria-label="Công ty cần làm mới">${COS.map(c=>`<option>${c}</option>`).join('')}</select>
   <button class="btn badb" data-act="resetAsk">Xóa dữ liệu…</button><span id="reset-confirm"></span></div></div>
  ${typeof sproGL==='function'?sproGL():''}</div>`;
}

/* ============ CALC (live form totals) ============ */
const CALC = {
  PR(f){ let t=0; f.querySelectorAll('#lines tr').forEach(tr=>{const m=mat(tr.querySelector('.li-mat').value);const q=num(tr.querySelector('.li-qty').value);tr.querySelector('.li-ref').textContent=fm(m.bp);tr.querySelector('.li-amt').textContent=fm(q*m.bp);t+=q*m.bp;});
    f.querySelector('#f-sum').innerHTML=`<span>Giá trị ước tính: <b>${fm(t)}</b></span>`; },
  PO(f){ let n=0; f.querySelectorAll('#polines tr').forEach(tr=>{const v=num(tr.dataset.qty)*num(tr.querySelector('.po-price').value);tr.querySelector('.po-amt').textContent=fm(v);n+=v;});
    const vat=Math.round(n*VATR()); const v=ven(f.querySelector('#f-vendor').value);
    f.querySelector('#f-sum').innerHTML=`<span>Tiền hàng <b>${fm(n)}</b></span><span>VAT <b>${fm(vat)}</b></span><span>Tổng <b>${fm(n+vat)}</b></span><span>Thanh toán sau <b>${v?v.terms:'—'}</b> ngày</span>`; },
  IV(f){ let n=0; f.querySelectorAll('.iv-line').forEach(tr=>{const q=num(tr.querySelector('.iv-qty').value),p=num(tr.querySelector('.iv-price').value),pp=num(tr.dataset.po);n+=q*p;const v=pp?(p-pp)/pp*100:0;const el=tr.querySelector('.iv-var');el.textContent=v.toFixed(2)+'%';el.style.color=Math.abs(v)>S.cfg.tol?'var(--bad)':'inherit';});
    n=Math.round(n); const vat=Math.round(n*VATR()), g=num(f.querySelector('#f-gross').value), diff=g-(n+vat);
    f.querySelector('#f-sum').innerHTML=`<span>Tiền hàng <b>${fm(n)}</b></span><span>VAT ${Math.round(VATR()*100)}% <b>${fm(vat)}</b></span><span>Hệ thống tính <b>${fm(n+vat)}</b></span><span>Chênh với HĐ <b style="color:${Math.abs(diff)>1?'var(--bad)':'var(--ok)'}">${fm(diff)}</b></span>`; },
  SO(f){ let n=0; f.querySelectorAll('#lines tr').forEach(tr=>{const q=num(tr.querySelector('.li-qty').value),p=num(tr.querySelector('.li-price').value);tr.querySelector('.li-amt').textContent=fm(q*p);n+=q*p;});
    const vat=Math.round(n*VATR()), tot=n+vat; f.querySelector('#f-sum').innerHTML=`<span>Tiền hàng <b>${fm(n)}</b></span><span>VAT <b>${fm(vat)}</b></span><span>Tổng <b>${fm(tot)}</b></span>`;
    const cu=f.querySelector('#f-cust').value; const e=calc(S.co).exposure(cu); const lim=(cus(cu)||{lim:0}).lim; const after=e.tot+tot;
    const box=f.querySelector('#f-credit'); box.className='note '+(after>lim&&S.cfg.credit!==false?'warn':'');
    box.innerHTML=`Hạn mức <b class="mono">${fm(lim)}</b> · đang sử dụng <b class="mono">${fm(e.tot)}</b> · sau đơn này <b class="mono">${fm(after)}</b>${after>lim&&S.cfg.credit!==false?' — <b>vượt hạn mức, đơn sẽ bị khóa tín dụng</b>':''}`; }
};

