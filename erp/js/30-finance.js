"use strict";
/* ERP Lab – Hiển thị chứng từ, mẫu in, báo cáo kế toán (FI). */
/* ============ DOCUMENT DETAIL ============ */
function parentOf(c,d){ const f={PO:'pr',GR:'po',IV:'po',PAY:'iv',DL:'so',BI:'dl',RC:'bi',CJ:'adv',ADS:'adv',JE:'revOf',BS:'ref'}[d.type]; return f&&d[f]?c.by[d[f]]:null; }
function childrenOf(c,d){ const m={PR:[['PO','pr']],PO:[['GR','po'],['IV','po']],IV:[['PAY','iv']],SO:[['DL','so']],DL:[['BI','dl']],BI:[['RC','bi']],ADV:[['CJ','adv'],['ADS','adv']],JE:[['JE','revOf']],PAY:[['BS','ref']],RC:[['BS','ref']]}[d.type]||[];
  return [].concat(...m.map(([t,f])=>c.T[t].filter(x=>x[f]===d.id))); }
function flowTree(c,cur){
  let root=cur; for(let i=0;i<6;i++){ const p=parentOf(c,root); if(!p) break; root=p; }
  const node = d => `<li><span class="node ${d.id===cur.id?'cur':''}">${docLink(S.param.co,d)} <span class="small">${esc(TYPES[d.type].n)}</span> ${chip(d)} <span class="small muted">${vd(d.date)} · ${fm(valueOf(d))}</span></span>${(()=>{const k=childrenOf(c,d);return k.length?`<ul>${k.map(node).join('')}</ul>`:'';})()}</li>`;
  return `<ul class="tree">${node(root)}</ul>`;
}
function itemsTable(d){
  const cols = {PR:['SL','Giá tham khảo'],PO:['SL','Đơn giá'],GR:['SL nhập','Giá tạm tính'],IV:['SL','Đơn giá HĐ'],SO:['SL','Đơn giá'],DL:['SL xuất','Giá vốn BQ'],BI:['SL','Đơn giá']}[d.type];
  if(!cols||!d.items) return '';
  const price = it => d.type==='PR'?mat(it.mat).bp : d.type==='DL'?(it.cost/it.qty) : it.price;
  return `<div class="tw"><table class="t"><thead><tr><th>Hàng hóa</th><th>ĐVT</th><th class="num">${cols[0]}</th><th class="num">${cols[1]}</th><th class="num">Thành tiền</th>${d.type==='IV'?'<th class="num">Giá đơn mua</th><th class="num">Lệch %</th>':''}</tr></thead><tbody>
  ${d.items.map(it=>{const p=price(it);const v=d.type==='IV'?((it.price-it.poPrice)/it.poPrice*100):0;
    return `<tr><td>${esc(it.mat)} · ${esc(mat(it.mat).n)}</td><td>${esc(mat(it.mat).u)}</td><td class="num">${it.qty}</td><td class="num">${fm(p)}</td><td class="num">${fm(p*it.qty)}</td>${d.type==='IV'?`<td class="num">${fm(it.poPrice)}</td><td class="num" style="color:${Math.abs(v)>S.cfg.tol?'var(--bad)':'inherit'}">${v.toFixed(2)}</td>`:''}</tr>`;}).join('')}</tbody>
  ${d.net!=null?`<tfoot><tr><td colspan="4">Cộng tiền hàng / Thuế GTGT / Tổng</td><td class="num">${fm(d.net)} / ${fm(d.vat)} / ${fm(d.total)}</td>${d.type==='IV'?'<td></td><td></td>':''}</tr></tfoot>`:''}</table></div>`;
}
function jeTable(d){
  const prop = (d.type==='JE'&&d.status==='pending'&&Array.isArray(d.lines)) ? d.lines : null;
  if(!prop&&(!Array.isArray(d.je)||!d.je.length||d.status==='rejected')) return `<p class="small muted" style="margin:0">${d.status==='rejected'?'Chứng từ bị từ chối/hủy nên không có bút toán hiệu lực.':d.status==='pending'?'Bút toán sẽ được ghi khi Kế toán trưởng duyệt.':'Chứng từ này không phát sinh bút toán kế toán (chứng từ nghiệp vụ).'}</p>`;
  const J = prop || d.je; const hasCC = J.some(j=>j.cc);
  return `${prop?'<p class="small" style="margin:0 0 6px"><b>Bút toán đề xuất</b> – chỉ ghi sổ khi Kế toán trưởng duyệt, vào ngày làm việc lúc duyệt.</p>':''}
  <div class="tw"><table class="t"><thead><tr><th>Tài khoản</th><th>Tên tài khoản</th><th>Đối tượng</th>${hasCC?'<th>TTCP</th>':''}<th>Diễn giải dòng</th><th class="num">Nợ</th><th class="num">Có</th></tr></thead><tbody>
  ${J.map(j=>`<tr><td class="mono">${esc(j.a)}</td><td>${esc(ACCS[j.a])}</td><td class="small">${esc(j.p||j.mat||'')}</td>${hasCC?`<td class="small mono">${esc(j.cc||'')}</td>`:''}<td class="small">${esc(j.memo||'')}</td><td class="num">${j.dr?fm(j.dr):''}</td><td class="num">${j.cr?fm(j.cr):''}</td></tr>`).join('')}</tbody>
  <tfoot><tr><td colspan="${hasCC?5:4}">Cộng${d.jeNo?' · Số bút toán '+esc(d.jeNo):''}${d.pdate?' · Ngày ghi sổ '+vd(d.pdate):''}</td><td class="num">${fm(sum(J,j=>j.dr||0))}</td><td class="num">${fm(sum(J,j=>j.cr||0))}</td></tr></tfoot></table></div>`;
}
const ACTN = {create:'Lập chứng từ',approve:'Phê duyệt',reject:'Từ chối'};
function histList(d){ return `<ul class="hist">${(d.hist||[]).map(h=>`<li><time>${vdt(h.at)}</time><div><b>${esc(ACTN[h.act]||h.act)}</b>${h.self?' <span class="chip c-pending">tự duyệt do kiêm nhiệm</span>':''} — ${esc(nameOf(h.by))} <span class="small muted">(${esc(roleName(h.role))})</span>${h.note?`<div class="small">${esc(h.note)}</div>`:''}</div></li>`).join('')}</ul>`; }
function nextSteps(c,d){
  const b=[]; const B=(tc,p,l)=>{ if(allowed(tc)) b.push(`<button class="btn sm pri" data-go="${tc}" data-p="${P(p)}">${esc(l)} (${tc})</button>`); };
  if(d.type==='PR'&&c.Q.prForPO.includes(d)) B('ME21N',{pr:d.id},'Lập đơn mua');
  if(d.type==='PO'&&c.Q.poForGR.includes(d)) B('MIGO',{po:d.id},'Nhập kho');
  if(d.type==='PO'&&c.Q.poForIV.includes(d)) B('MIRO',{po:d.id},'Nhập hóa đơn');
  if(d.type==='IV'&&c.Q.ivForPay.includes(d)) B('F-53',{iv:d.id},'Đề nghị chi');
  if(d.type==='SO'&&c.Q.soForDL.includes(d)) B('VL01N',{so:d.id},'Xuất kho');
  if(d.type==='DL'&&c.Q.dlForBI.includes(d)) B('VF01',{dl:d.id},'Lập hóa đơn');
  if(d.type==='BI'&&c.Q.biForRC.includes(d)) B('F-28',{bi:d.id},'Thu tiền');
  return b.join('');
}
function approvalPanel(c,d){
  const pend = (['PR','PO','PAY','RC','JE','CJ','CNT','ADV','ADS'].includes(d.type)&&d.status==='pending')||(['IV','SO'].includes(d.type)&&d.status==='blocked');
  if(!pend) return '';
  if(!allowed('SBWP')) return `<div class="note warn">Chứng từ đang chờ <b>Kế toán trưởng</b> xử lý.</div>`;
  let info='';
  if(d.type==='PAY'){ const b=c.bal(d.acc); info=`<dl class="kv"><dt>Số dư TK ${d.acc} hiện tại</dt><dd class="mono" style="color:${b<d.amount?'var(--bad)':'inherit'}">${fm(b)}</dd><dt>Số tiền đề nghị chi</dt><dd class="mono">${fm(d.amount)}</dd><dt>Hóa đơn gốc</dt><dd>${docLink(S.param.co,c.by[d.iv])}</dd></dl>`; }
  if(d.type==='RC'){ info=`<dl class="kv"><dt>Số tiền</dt><dd class="mono">${fm(d.amount)}</dd><dt>Chứng từ ngân hàng</dt><dd>${esc(d.ref)}</dd><dt>Hóa đơn</dt><dd>${docLink(S.param.co,c.by[d.bi])}</dd></dl>`; }
  if(d.type==='SO'){ const e=c.exposure(d.cust); info=`<dl class="kv"><dt>Hạn mức tín dụng</dt><dd class="mono">${fm(cus(d.cust).lim)}</dd><dt>Dư nợ TK 131</dt><dd class="mono">${fm(e.ar)}</dd><dt>Đơn bán chưa xuất HĐ (kể cả đơn này)</dt><dd class="mono">${fm(e.so+d.total)}</dd><dt>Vượt hạn mức</dt><dd class="mono" style="color:var(--bad)">${fm(e.tot+d.total-cus(d.cust).lim)}</dd></dl>`; }
  if(d.type==='IV') info=`<p class="small" style="margin:0">Hóa đơn có đơn giá lệch vượt ${S.cfg.tol}% so với đơn mua (xem cột Lệch %). Gỡ khóa nếu chênh lệch đã được thương lượng; hủy nếu cần nhà cung cấp lập hóa đơn điều chỉnh.</p>`;
  if(d.type==='PO'){ const v=ven(d.vendor); info=`<p class="small" style="margin:0">Nhà cung cấp ${esc(v.c)} – hệ số giá ${v.f}, thời hạn thanh toán ${v.terms} ngày. Đối chiếu với bảng báo giá và đề nghị mua ${docLink(S.param.co,c.by[d.pr])}.</p>`; }
  if(d.type==='CJ'&&d.dir==='out'){ const b=c.bal('111'); info=`<dl class="kv"><dt>Tồn quỹ tiền mặt hiện tại</dt><dd class="mono" style="color:${b<d.amount?'var(--bad)':'inherit'}">${fm(b)}</dd><dt>Số tiền chi</dt><dd class="mono">${fm(d.amount)}</dd></dl>`; }
  if(d.type==='JE') info=`<p class="small" style="margin:0">Kiểm tra căn cứ, tài khoản, trung tâm chi phí và kỳ ghi sổ. Bút toán ghi vào ngày làm việc <b>${vd(today())}</b>; kỳ này phải đang mở.${d.kind==='acc'?' Bút toán trích trước sẽ tự đảo ngày '+vd(d.revDate)+'.':''}</p>`;
  if(d.type==='CNT') info=`<dl class="kv"><dt>Tồn quỹ theo sổ</dt><dd class="mono">${fm(d.book)}</dd><dt>Thực tế kiểm đếm</dt><dd class="mono">${fm(d.counted)}</dd><dt>Chênh lệch</dt><dd class="mono" style="color:var(--bad)">${fm(d.diff)} (${d.diff<0?'thiếu → TK 1381':'thừa → TK 3381'})</dd></dl>`;
  if(d.type==='ADS') info=`<dl class="kv"><dt>Đã tạm ứng</dt><dd class="mono">${fm(d.advAmount)}</dd><dt>Đã chi theo chứng từ gốc</dt><dd class="mono">${fm(d.expTotal)}</dd><dt>${d.ret>=0?'Nộp lại quỹ':'Chi bổ sung'}</dt><dd class="mono">${fm(Math.abs(d.ret))}</dd></dl>`;
  const okL = {PR:'Phê duyệt',PO:'Phê duyệt đơn mua',IV:'Gỡ khóa thanh toán',SO:'Gỡ khóa tín dụng',PAY:'Duyệt chi',RC:'Duyệt thu',JE:'Duyệt và ghi sổ',CJ:'Duyệt phiếu',CNT:'Duyệt xử lý chênh lệch',ADV:'Duyệt tạm ứng',ADS:'Duyệt quyết toán'}[d.type];
  const noL = {IV:'Hủy hóa đơn'}[d.type]||'Từ chối';
  return `<div class="panel" style="border-color:var(--warn)"><h2>Phê duyệt</h2>${info}
   <form class="form" data-form="DECIDE" data-co="${esc(S.param.co)}" data-id="${esc(d.id)}" style="margin-top:12px"><div class="err"></div>
   <label class="field"><span>Ý kiến (bắt buộc khi từ chối)</span><input id="f-note" maxlength="200"></label>
   <div style="display:flex;gap:8px;flex-wrap:wrap"><button class="btn okb" name="ok" value="1">${okL}</button><button class="btn badb" name="ok" value="0">${noL}</button></div></form></div>`;
}
function scrDoc(){
  const p = S.param||{}; const co = p.co||S.co;
  if(!S.isAdmin && co!==S.co) return `<div class="wrap"><div class="err">Bạn chỉ xem được chứng từ của công ty mình.</div></div>`;
  const c = calc(co); const d = c.by[p.id];
  if(!d) return `<div class="wrap">${head('FB03','Không tìm thấy chứng từ','Chứng từ có thể đã bị xóa khi giảng viên làm mới dữ liệu.')}</div>`;
  return `<div class="wrap">${head(TYPES[d.type].tc+' · Hiển thị',TYPES[d.type].n+' '+d.no,'Lập lúc '+vdt(d.at)+' bởi '+esc(nameOf(d.by))+' ('+esc(roleName(d.role))+')',nextSteps(c,d))}
  ${approvalPanel(c,d)}
  <div class="cols">
   <div class="panel"><h2>Thông tin chung</h2><dl class="kv">
    <dt>Trạng thái</dt><dd>${chip(d)}</dd><dt>Ngày chứng từ</dt><dd>${vd(d.date)}</dd>
    ${d.vendor||d.cust?`<dt>Đối tượng</dt><dd>${esc(d.vendor||d.cust)} · ${esc(partnerOf(d))}</dd>`:''}
    ${d.reason?`<dt>Lý do</dt><dd>${esc(d.reason)}</dd>`:''}${d.need?`<dt>Ngày cần/giao</dt><dd>${vd(d.need)}</dd>`:''}
    ${d.invNo?`<dt>Hóa đơn</dt><dd class="mono">${esc(d.invSym)} / ${esc(d.invNo)}</dd>`:''}${d.due?`<dt>Hạn thanh toán</dt><dd>${vd(d.due)}</dd>`:''}
    ${d.dn?`<dt>Phiếu giao hàng NCC</dt><dd>${esc(d.dn)} · ${esc(d.deliverer)}</dd>`:''}${d.receiver?`<dt>Người nhận</dt><dd>${esc(d.receiver)} ${esc(d.vehicle||'')}</dd>`:''}
    ${d.custPo?`<dt>Đơn đặt hàng của khách</dt><dd>${esc(d.custPo)}</dd>`:''}${d.amount!=null?`<dt>Số tiền</dt><dd class="mono">${fm(d.amount)}${d.type==='PAY'||d.type==='RC'?' ('+(d.acc==='111'?'tiền mặt':'chuyển khoản'+(d.clr?', qua TK 113 chờ sao kê':''))+')':''}</dd>`:''}
    ${d.memo?`<dt>Nội dung</dt><dd>${esc(d.memo)}</dd>`:''}${d.ref?`<dt>Chứng từ NH</dt><dd>${esc(d.ref)}</dd>`:''}${d.note?`<dt>Ghi chú</dt><dd>${esc(d.note)}</dd>`:''}
    ${d.blockReason?`<dt>Lý do khóa</dt><dd>${esc(d.blockReason)}</dd>`:''}
    ${d.pdate?`<dt>Ngày ghi sổ</dt><dd>${vd(d.pdate)}</dd>`:''}${d.kind?`<dt>Loại bút toán</dt><dd>${esc({man:'Bút toán tay (FB50)',acc:'Trích trước, tự đảo (FBS1)',rev:'Bút toán đảo (FB08)'}[d.kind]||d.kind)}${d.auto?' – hệ thống tự đảo':''}</dd>`:''}
    ${d.revOf?`<dt>Đảo của chứng từ</dt><dd>${docLink(co,{id:d.revOf,no:d.revNo||d.revOf})}</dd>`:''}${d.revBy?`<dt>Đã bị đảo bởi</dt><dd>${docLink(co,{id:d.revBy,no:d.revNo||d.revBy})}</dd>`:''}
    ${d.revDate&&d.kind==='acc'?`<dt>Ngày tự đảo</dt><dd>${vd(d.revDate)}</dd>`:''}
    ${d.type==='CJ'?`<dt>Loại phiếu</dt><dd>${d.dir==='in'?'Phiếu thu':'Phiếu chi'} – TK đối ứng ${esc(d.acc)}${d.cc?' · '+esc(d.cc):''}</dd><dt>${d.dir==='in'?'Người nộp':'Người nhận'}</dt><dd>${esc(d.person||'')}</dd>`:''}
    ${d.type==='CNT'?`<dt>Ban kiểm kê</dt><dd>${esc(d.members||'')}</dd><dt>Sổ / thực tế / chênh lệch</dt><dd class="mono">${fm(d.book)} / ${fm(d.counted)} / ${fm(d.diff)}</dd>`:''}
    ${d.type==='ADV'||d.type==='ADS'?`<dt>Người tạm ứng</dt><dd>${esc(d.empName||'')} <span class="mono small">${esc(d.emp||'')}</span></dd>`:''}${d.purpose?`<dt>Lý do tạm ứng</dt><dd>${esc(d.purpose)}</dd>`:''}
    ${d.type==='BS'?`<dt>Dòng sao kê</dt><dd><span class="mono">${esc(d.line)}</span> · ${vd(d.vdate)} · ${esc(d.descr)}</dd>`:''}
   </dl></div>
   <div class="panel"><h2>Luồng chứng từ</h2>${flowTree(c,d)}</div>
  </div>
  ${d.items?`<div><h3 class="sec-title">Chi tiết hàng hóa</h3>${itemsTable(d)}</div>`:''}
  ${d.type==='ADS'&&Array.isArray(d.lines)?`<div><h3 class="sec-title">Các khoản đã chi</h3><div class="tw"><table class="t"><thead><tr><th>TK chi phí</th><th>TTCP</th><th>Nội dung, chứng từ gốc</th><th class="num">Số tiền</th></tr></thead><tbody>${d.lines.map(x=>`<tr><td class="mono">${esc(x.a)} <span class="small">${esc(ACCS[x.a]||'')}</span></td><td class="mono small">${esc(x.cc||'')}</td><td>${esc(x.memo)}</td><td class="num">${fm(x.amount)}</td></tr>`).join('')}</tbody></table></div></div>`:''}
  <div><h3 class="sec-title">Bút toán kế toán (TT 99/2025)</h3>${jeTable(d)}</div>
  <div class="panel"><h2>Nhật ký luân chuyển & phê duyệt</h2>${histList(d)}</div>
  <details class="vbox"><summary>Xem mẫu chứng từ in</summary>${voucher(c,co,d)}</details></div>`;
}
function signer(d,act){ const h=(d.hist||[]).find(x=>x.act===act); return h?`<div class="sg">Đã ký điện tử<br>${esc(nameOf(h.by))}<br>${vdt(h.at)}</div>`:`<div class="sg none">(chưa ký)</div>`; }
function voucher(c,co,d){
  const t = {PR:['GIẤY ĐỀ NGHỊ MUA HÀNG'],PO:['ĐƠN ĐẶT HÀNG'],GR:['PHIẾU NHẬP KHO'],IV:['PHIẾU ĐỐI CHIẾU HÓA ĐƠN MUA VÀO'],PAY:[d.acc==='111'?'PHIẾU CHI':'ỦY NHIỆM CHI'],
    SO:['XÁC NHẬN ĐƠN HÀNG'],DL:['PHIẾU XUẤT KHO'],BI:['HÓA ĐƠN GIÁ TRỊ GIA TĂNG'],RC:[d.acc==='111'?'PHIẾU THU':'GIẤY BÁO CÓ (bản ghi nhận)'],OB:['CHỨNG TỪ MỞ SỔ – SỐ DƯ ĐẦU KỲ'],
    JE:['CHỨNG TỪ GHI SỔ (BÚT TOÁN TỔNG HỢP)'],CJ:[d.dir==='in'?'PHIẾU THU':'PHIẾU CHI'],CNT:['BIÊN BẢN KIỂM KÊ QUỸ'],BS:['CHỨNG TỪ GHI SỔ THEO SAO KÊ NGÂN HÀNG'],
    ADV:['GIẤY ĐỀ NGHỊ TẠM ỨNG'],ADS:['GIẤY THANH TOÁN TIỀN TẠM ỨNG']}[d.type][0];
  const ns = d.je&&d.je.length?`Nợ: ${[...new Set(d.je.filter(j=>j.dr).map(j=>j.a))].join(', ')} — Có: ${[...new Set(d.je.filter(j=>j.cr).map(j=>j.a))].join(', ')}`:'';
  const total = valueOf(d);
  const appr = ['PR','PO','PAY','RC','JE','CJ','CNT','ADV','ADS'].includes(d.type) || (d.hist||[]).some(h=>h.act==='approve');
  let body='';
  if(d.items){ body = itemsTable(d); }
  return `<div class="voucher"><div class="v-head"><div><b>${esc(coName(co))}</b><br>MST: 42010${co.slice(1)}8899 · Nha Trang, Khánh Hòa</div><div style="text-align:right">Mẫu tham khảo – mô phỏng<br>${ns?esc(ns):''}</div></div>
  <div class="v-title">${t}</div><div class="v-sub">Số: ${esc(d.no)}${d.invNo?' · Ký hiệu '+esc(d.invSym)+' Số '+esc(d.invNo):''} · Ngày ${vd(d.date)}</div>
  ${d.vendor||d.cust?`<p style="margin:4px 0">${d.vendor?'Nhà cung cấp':'Khách hàng'}: <b>${esc(partnerOf(d))}</b> — MST ${esc((ven(d.vendor)||cus(d.cust)).mst)}</p>`:''}
  ${d.reason?`<p style="margin:4px 0">Lý do: ${esc(d.reason)}</p>`:''}${d.memo?`<p style="margin:4px 0">Nội dung: ${esc(d.memo)}</p>`:''}
  ${d.person?`<p style="margin:4px 0">${d.dir==='in'?'Họ tên người nộp tiền':'Họ tên người nhận tiền'}: <b>${esc(d.person)}</b></p>`:''}${d.empName?`<p style="margin:4px 0">Người tạm ứng: <b>${esc(d.empName)}</b>${d.purpose?' — Lý do: '+esc(d.purpose):''}</p>`:''}
  ${body}${d.type==='JE'||d.type==='CNT'||d.type==='BS'?jeTable(d):''}
  <p style="margin:6px 0">Tổng số tiền: <b class="mono">${fm(total)}</b> đồng<br><i>Bằng chữ: ${esc(docSo(total))}</i></p>
  ${d.type==='BI'?'<p class="small muted">Hóa đơn mô phỏng phục vụ học tập, không có giá trị pháp lý.</p>':''}
  <div class="signs"><div><b>Người lập</b>${signer(d,'create')}</div>${appr?`<div><b>Kế toán trưởng / Người duyệt</b>${signer(d,'approve')}</div>`:''}
  ${d.type==='GR'?`<div><b>Người giao hàng</b><div class="sg none">${esc(d.deliverer||'')}</div></div>`:''}${d.type==='DL'?`<div><b>Người nhận hàng</b><div class="sg none">${esc(d.receiver||'')}</div></div>`:''}</div></div>`;
}

/* ============ REPORTS ============ */
function scrStock(){
  const c = calc(S.co); const m = S.param&&S.param.mat;
  if(m){ const s=c.st[m]; let run=s.oq;
    return `<div class="wrap">${head('MMBE','Thẻ kho '+esc(m)+' · '+esc(mat(m).n),'Theo dõi số lượng nhập – xuất – tồn theo từng chứng từ.')}
    <div class="tw"><table class="t"><thead><tr><th>Ngày</th><th>Chứng từ</th><th>Diễn giải</th><th class="num">Nhập</th><th class="num">Xuất</th><th class="num">Tồn</th></tr></thead><tbody>
    <tr><td></td><td></td><td>Tồn đầu kỳ</td><td></td><td></td><td class="num">${s.oq}</td></tr>
    ${s.mv.slice().sort((a,b)=>String(a.d.at).localeCompare(String(b.d.at))).map(x=>{run+=x.q;return `<tr><td>${vd(x.d.date)}</td><td>${docLink(S.co,x.d)}</td><td>${x.q>0?'Nhập mua từ '+esc(x.d.vendor):'Xuất bán cho '+esc(x.d.cust)}</td><td class="num">${x.q>0?x.q:''}</td><td class="num">${x.q<0?-x.q:''}</td><td class="num">${run}</td></tr>`;}).join('')}
    </tbody></table></div></div>`; }
  const sm = MATS.filter(isStock); const tk = INV_ACCS.filter(a=>sm.some(x=>(x.acc||'156')===a));
  return `<div class="wrap">${head('MMBE','Tồn kho vật tư','Giá trị tồn theo tài khoản tồn kho của từng loại vật tư (152 nguyên vật liệu, 155 thành phẩm, 156 hàng hóa), đơn giá bình quân gia quyền di động do máy chủ tính. Bấm vào mã để xem thẻ kho.')}
  <div class="tw"><table class="t"><thead><tr><th>Mã</th><th>Tên vật tư</th><th>Loại · TK</th><th>ĐVT</th><th class="num">Tồn đầu</th><th class="num">Nhập</th><th class="num">Xuất</th><th class="num">Tồn cuối</th><th class="num">Tồn tối thiểu</th><th class="num">Đơn giá BQ</th><th class="num">Giá trị tồn</th></tr></thead><tbody>
  ${sm.map(x=>{const s=c.st[x.c];const low=x.min>0&&s.q<x.min;return `<tr class="click" data-go="MMBE" data-p="${P({mat:x.c})}"><td class="mono">${x.c}</td><td>${esc(x.n)}${x.active===false?' <span class="chip c-rejected">Khóa</span>':''}</td><td class="small">${esc(x.t)} · ${esc(x.acc||'156')}</td><td>${esc(x.u)}</td><td class="num">${s.oq}</td><td class="num">${s.iq}</td><td class="num">${s.xq}</td><td class="num"><b>${s.q}</b>${low?' <span class="chip c-pending">dưới mức</span>':''}</td><td class="num">${x.min||''}</td><td class="num">${fm(s.avg)}</td><td class="num">${fm(s.v)}</td></tr>`;}).join('')}</tbody>
  <tfoot>${tk.map(a=>`<tr><td colspan="10">Cộng TK ${a} (số dư sổ cái: ${fm(c.bal(a))})</td><td class="num">${fm(sum(sm.filter(x=>(x.acc||'156')===a),x=>c.st[x.c].v))}</td></tr>`).join('')}</tfoot></table></div></div>`;
}
function scrAP(){
  const c = calc(S.co);
  const openIV = c.T.IV.filter(i=>i.status!=='rejected'&&i.total-c.ivPaid(i)>0.5);
  const grNoInv = c.T.PO.filter(p=>p.status==='approved').map(p=>({p,v:sum(p.items.map((it,i)=>c.poUninv(p)[i]*it.price))})).filter(x=>x.v>0);
  return `<div class="wrap">${head('FBL1N','Công nợ phải trả người bán','Số dư TK 331 chi tiết theo nhà cung cấp và các khoản chưa thanh toán.')}
  <div class="tw"><table class="t"><thead><tr><th>Nhà cung cấp</th><th class="num">Phát sinh Nợ</th><th class="num">Phát sinh Có</th><th class="num">Dư Có cuối kỳ</th></tr></thead><tbody>
  ${VENDORS.map(v=>`<tr><td>${v.c} · ${esc(v.n)}</td><td class="num">${fm(c.ap[v.c].dr)}</td><td class="num">${fm(c.ap[v.c].cr)}</td><td class="num"><b>${fm(c.ap[v.c].cr-c.ap[v.c].dr)}</b></td></tr>`).join('')}</tbody>
  <tfoot><tr><td>Cộng</td><td class="num">${fm(sum(VENDORS,v=>c.ap[v.c].dr))}</td><td class="num">${fm(sum(VENDORS,v=>c.ap[v.c].cr))}</td><td class="num">${fm(-c.bal('331'))}</td></tr></tfoot></table></div>
  <div><h3 class="sec-title">Hóa đơn chưa thanh toán hết</h3>${pickTable(openIV,[{h:'Hóa đơn',f:i=>docLink(S.co,i)},{h:'NCC',f:i=>esc(i.vendor)},{h:'Hạn',f:i=>vd(i.due)+(i.due<today()?' <span class="chip c-rejected">Quá hạn</span>':'')},{h:'Trạng thái',f:chip},{h:'Còn nợ',n:1,f:i=>fm(i.total-c.ivPaid(i))}])}</div>
  <div><h3 class="sec-title">Hàng đã nhập kho chưa có hóa đơn (giá tạm tính)</h3>${pickTable(grNoInv,[{h:'Đơn mua',f:x=>docLink(S.co,x.p)},{h:'NCC',f:x=>esc(x.p.vendor)},{h:'Giá trị tạm tính',n:1,f:x=>fm(x.v)}])}</div></div>`;
}
function scrAR(){
  const c = calc(S.co);
  const openBI = c.T.BI.filter(i=>i.total-c.biPaid(i)>0.5);
  return `<div class="wrap">${head('FBL5N','Công nợ phải thu & hạn mức tín dụng','Số dư TK 131 theo khách hàng, mức sử dụng hạn mức gồm cả đơn bán đã xác nhận nhưng chưa xuất hóa đơn.')}
  <div class="tw"><table class="t"><thead><tr><th>Khách hàng</th><th class="num">Hạn mức</th><th class="num">Dư nợ 131</th><th class="num">Đơn chưa xuất HĐ</th><th class="num">Tổng sử dụng</th><th>Mức dùng</th></tr></thead><tbody>
  ${CUSTS.map(x=>{const e=c.exposure(x.c);const pc=Math.min(100,e.tot/x.lim*100);return `<tr><td>${x.c} · ${esc(x.n)}</td><td class="num">${fm(x.lim)}</td><td class="num">${fm(e.ar)}</td><td class="num">${fm(e.so)}</td><td class="num"><b>${fm(e.tot)}</b></td><td><div class="bar" title="${pc.toFixed(0)}%"><i class="${pc>=100?'hi':pc>75?'mid':''}" style="width:${pc}%"></i></div></td></tr>`;}).join('')}</tbody></table></div>
  <div><h3 class="sec-title">Hóa đơn bán chưa thu hết</h3>${pickTable(openBI,[{h:'Hóa đơn',f:i=>docLink(S.co,i)},{h:'Khách hàng',f:i=>esc(i.cust)},{h:'Hạn thu',f:i=>vd(i.due)+(i.due<today()?' <span class="chip c-rejected">Quá hạn</span>':'')},{h:'Còn phải thu',n:1,f:i=>fm(i.total-c.biPaid(i))}])}</div></div>`;
}
function scrNKC(){
  const c = calc(S.co);
  const L = c.lines.slice().sort((a,b)=>String((a.d.pdate||a.d.date)+a.d.at).localeCompare(String((b.d.pdate||b.d.date)+b.d.at)));
  return `<div class="wrap">${head('ZNKC','Sổ Nhật ký chung','Ghi theo trình tự thời gian mọi bút toán đã ghi sổ (không gồm số dư đầu kỳ).')}
  ${L.length?`<div class="tw"><table class="t"><thead><tr><th>Ngày GS</th><th>Số CT</th><th>Diễn giải</th><th>TK</th><th>Đối tượng</th><th class="num">Nợ</th><th class="num">Có</th></tr></thead><tbody>
  ${L.map(x=>`<tr><td>${vd(x.d.pdate||x.d.date)}</td><td>${docLink(S.co,x.d)}</td><td class="small">${esc(TYPES[x.d.type].n)}${x.d.vendor?' – '+esc(x.d.vendor):x.d.cust?' – '+esc(x.d.cust):''}${x.d.memo&&x.d.type!=='RC'?' – '+esc(x.d.memo):''}</td><td class="mono">${esc(x.j.a)}</td><td class="small">${esc(x.j.p||x.j.mat||'')}</td><td class="num">${x.j.dr?fm(x.j.dr):''}</td><td class="num">${x.j.cr?fm(x.j.cr):''}</td></tr>`).join('')}</tbody>
  <tfoot><tr><td colspan="5">Cộng phát sinh</td><td class="num">${fm(sum(L,x=>x.j.dr||0))}</td><td class="num">${fm(sum(L,x=>x.j.cr||0))}</td></tr></tfoot></table></div>`:`<div class="tw"><div class="empty">Chưa có bút toán. Bút toán phát sinh từ MIGO, MIRO, VL01N, VF01 và phiếu chi/thu đã duyệt.</div></div>`}</div>`;
}
function scrTB(){
  const c = calc(S.co); let t={od:0,oc:0,dr:0,cr:0,cd:0,cc:0};
  const rows = Object.keys(ACCS).filter(a=>c.acc[a]&&(c.acc[a].o||c.acc[a].dr||c.acc[a].cr)).sort().map(a=>{const x=c.acc[a];const cl=x.o+x.dr-x.cr;const r={a,od:x.o>0?x.o:0,oc:x.o<0?-x.o:0,dr:x.dr,cr:x.cr,cd:cl>0?cl:0,cc:cl<0?-cl:0};Object.keys(t).forEach(k=>t[k]+=r[k]);return r;});
  const ok = Math.abs(t.dr-t.cr)<1 && Math.abs(t.cd-t.cc)<1;
  return `<div class="wrap">${head('F.01','Bảng cân đối số phát sinh','Số dư đầu kỳ, phát sinh trong kỳ và số dư cuối kỳ của các tài khoản dùng trong hai chu trình.')}
  <div class="note ${ok?'ok':'bad'}">${ok?'Tổng phát sinh Nợ bằng tổng phát sinh Có; tổng dư Nợ bằng tổng dư Có.':'<b>Bảng không cân.</b> Kiểm tra lại bút toán.'}</div>
  <div class="tw"><table class="t"><thead><tr><th>TK</th><th>Tên tài khoản</th><th class="num">Dư Nợ đầu</th><th class="num">Dư Có đầu</th><th class="num">PS Nợ</th><th class="num">PS Có</th><th class="num">Dư Nợ cuối</th><th class="num">Dư Có cuối</th></tr></thead><tbody>
  ${rows.map(r=>`<tr><td class="mono">${r.a}</td><td>${esc(ACCS[r.a])}</td>${['od','oc','dr','cr','cd','cc'].map(k=>`<td class="num">${r[k]?fm(r[k]):''}</td>`).join('')}</tr>`).join('')}</tbody>
  <tfoot><tr><td colspan="2">Cộng</td>${['od','oc','dr','cr','cd','cc'].map(k=>`<td class="num">${fm(t[k])}</td>`).join('')}</tr></tfoot></table></div></div>`;
}

