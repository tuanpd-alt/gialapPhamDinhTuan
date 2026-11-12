"use strict";
/* ERP Lab – Trang làm việc, Mua hàng (MM), Bán hàng (SD), hộp phê duyệt, danh sách. */
/* ============ SCREEN: HOME ============ */
const P2P = [['ME51N','KHO','Đề nghị mua',c=>null],['ME54N','KTT','Duyệt đề nghị',c=>c.Q.ap.PR.length],['ME21N','MH','Lập đơn mua',c=>c.Q.prForPO.length],['ME29N','KTT','Duyệt đơn mua',c=>c.Q.ap.PO.length],
  ['MIGO','KHO','Nhập kho',c=>c.Q.poForGR.length],['MIRO','AP','Đối chiếu hóa đơn',c=>c.Q.poForIV.length],['MRBR','KTT','Gỡ khóa HĐ (nếu có)',c=>c.Q.ap.IV.length],['F-53','AP','Đề nghị chi',c=>c.Q.ivForPay.length],['ZFAP','KTT','Duyệt chi',c=>c.Q.ap.PAY.length]];
const O2C = [['VA01','KD','Đơn bán hàng',c=>null],['VKM3','KTT','Gỡ khóa tín dụng',c=>c.Q.ap.SO.length],['VL01N','KHO','Xuất kho giao hàng',c=>c.Q.soForDL.length],['VF01','AR','Lập hóa đơn GTGT',c=>c.Q.dlForBI.length],
  ['F-28','AR','Ghi nhận thu tiền',c=>c.Q.biForRC.length],['ZFAP','KTT','Duyệt thu',c=>c.Q.ap.RC.length]];
function lane(steps,c){
  return `<div class="lane">${steps.map((s,i)=>{ const q=s[3](c); const mine=S.role!=='GV'&&(expandRoles(myRoles()).includes(s[1])||(s[1]==='KTT'&&canApprove()));
    return (i?'<span class="arrow" aria-hidden="true">→</span>':'')+`<button class="step ${mine?'mine':''}" style="--rc:var(--r-${s[1]})" data-go="${s[0]}">${q!=null?`<span class="q ${q?'has':''}">${q}</span>`:''}<code>${s[0]}</code><span class="s">${esc(s[2])}</span><span class="r">${esc(ROLES[s[1]].n)}</span></button>`; }).join('')}</div>`;
}
function scrHome(){
  const c = calc(S.co);
  const me = S.me?S.me.full_name:'';
  const tiles = [];
  const T = (tc,n,l) => { if(allowed(tc)) tiles.push(`<button class="tile" data-go="${tc}"><span class="n ${n?'':'zero'}">${n}</span><span class="l">${esc(l)}</span><code>${tc}</code></button>`); };
  T('SBWP',c.Q.apAll.length,'Chứng từ chờ bạn phê duyệt');
  if(typeof mdPendingCount==='function') T('ZMDA',mdPendingCount(S.co),'Thay đổi dữ liệu gốc chờ duyệt');
  T('FBV0',c.Q.ap.JE.length+c.Q.ap.CJ.length+c.Q.ap.CNT.length+c.Q.ap.ADV.length+c.Q.ap.ADS.length,'Bút toán, phiếu quỹ, tạm ứng chờ duyệt');
  if(TC.FF67&&allowed('FF67')) T('FF67',((mdOf(S.co)||{}).bank||[]).filter(b=>b.st==='open').length,'Dòng sao kê ngân hàng chưa xử lý');
  T('ME21N',c.Q.prForPO.length,'Đề nghị mua đã duyệt, chờ lập đơn mua');
  T('MIGO',c.Q.poForGR.length,'Đơn mua đã duyệt, chờ nhập kho');
  T('VL01N',c.Q.soForDL.length,'Đơn bán đã xác nhận, chờ xuất kho');
  T('MIRO',c.Q.poForIV.length,'Hàng đã nhập, chờ hóa đơn nhà cung cấp');
  T('F-53',c.Q.ivForPay.length,'Hóa đơn mua chờ đề nghị thanh toán');
  T('VF01',c.Q.dlForBI.length,'Phiếu xuất kho chờ lập hóa đơn');
  T('F-28',c.Q.biForRC.length,'Hóa đơn bán chờ thu tiền');
  const mine = c.L.filter(d=>d.by===S.uid).slice(-6).reverse();
  const myRej = c.L.filter(d=>d.by===S.uid&&d.status==='rejected');
  return `<div class="wrap">
  <div class="ph"><div><div class="tc">${esc(S.co)} · ${esc(coName(S.co))}</div><h1>Xin chào${me?', '+esc(me):''}</h1><p>Vai trò: <b>${esc(S.isAdmin?roleName(S.role):rolesLabel(S.me))}</b>${S.role&&ROLES[S.role]&&myRoles().length<2&&!myGrants().length?' — '+esc(ROLES[S.role].d):''}. Gõ mã giao dịch ở ô phía trên hoặc chọn bước trong sơ đồ quy trình.</p></div></div>
  ${myRej.length?`<div class="note bad"><b>${myRej.length} chứng từ của bạn bị từ chối.</b> Mở chứng từ để xem lý do rồi lập lại: ${myRej.map(d=>docLink(S.co,d)).join(', ')}</div>`:''}
  ${tiles.length?`<div><h3 class="sec-title">Việc cần làm</h3><div class="tiles">${tiles.join('')}</div></div>`:''}
  <div class="panel"><h2>Sơ đồ quy trình của công ty</h2>
    <div class="flowmap"><div><div class="lane-l">Mua hàng – Thanh toán (Procure-to-Pay)</div>${lane(P2P,c)}</div>
    <div><div class="lane-l">Bán hàng – Thu tiền (Order-to-Cash)</div>${lane(O2C,c)}</div></div>
    <p class="small muted" style="margin-bottom:0">Số đỏ ở góc là số chứng từ đang nằm chờ ở bước đó. Ô có viền đậm là bước thuộc vai trò của bạn.</p></div>
  <div class="cols">
    <div class="panel"><h2>Chứng từ bạn lập gần đây</h2>${mine.length?`<div class="tw"><table class="t"><tbody>${mine.map(d=>`<tr class="click" data-go="DOC" data-p="${P({co:S.co,id:d.id})}"><td class="mono">${esc(d.no)}</td><td>${esc(TYPES[d.type].n)}</td><td>${chip(d)}</td></tr>`).join('')}</tbody></table></div>`:'<p class="muted small" style="margin:0">Chưa có. Chứng từ bạn lập sẽ hiện ở đây.</p>'}</div>
    <div class="panel"><h2>Số dư nhanh</h2><dl class="kv">
      <dt>TK 112 Tiền gửi</dt><dd class="mono">${fm(c.bal('112'))}</dd>
      <dt>TK 111 Tiền mặt</dt><dd class="mono">${fm(c.bal('111'))}</dd>
      <dt>TK 152, 155, 156 Tồn kho</dt><dd class="mono">${fm(c.bal('152')+c.bal('155')+c.bal('156'))}</dd>
      <dt>TK 131 Phải thu</dt><dd class="mono">${fm(c.bal('131'))}</dd>
      <dt>TK 331 Phải trả</dt><dd class="mono">${fm(-c.bal('331'))}</dd></dl></div>
  </div></div>`;
}

/* ============ LINE ITEM HELPERS ============ */
const lineMats = (kind,co) => kind==='SO'?sellMats(co):buyMats(co);
function matOpts(sel,co,kind){ const c=calc(co); return lineMats(kind,co).map(m=>`<option value="${m.c}" ${m.c===sel?'selected':''}>${m.c} · ${esc(m.n)} (tồn ${c.st[m.c]?c.st[m.c].q:0} ${esc(m.u)})</option>`).join(''); }
function lineRow(kind,co){
  const m = lineMats(kind,co)[0] || MAT_NONE;
  return `<tr><td><select class="li-mat w-mat" data-chg="linemat" aria-label="Vật tư">${matOpts(m.c,co,kind)}</select></td>
  <td><input class="li-qty num" type="number" min="1" step="1" value="1" aria-label="Số lượng"></td>
  ${kind==='SO'?`<td><input class="li-price num" type="number" min="0" step="1000" value="${m.sp}" aria-label="Đơn giá"></td>`:`<td class="num li-ref">${fm(m.bp)}</td>`}
  <td class="num li-amt"></td><td><button type="button" class="btn sm" data-act="delLine" aria-label="Xóa dòng">✕</button></td></tr>`;
}
function lineTable(kind,co){
  return `<div class="tw"><table class="t"><thead><tr><th>Hàng hóa</th><th class="num">Số lượng</th><th class="num">${kind==='SO'?'Đơn giá bán (chưa VAT)':'Giá tham khảo'}</th><th class="num">${kind==='SO'?'Thành tiền':'Giá trị ước tính'}</th><th></th></tr></thead><tbody id="lines">${lineRow(kind,co)}</tbody></table></div>
  <div><button type="button" class="btn sm" data-act="addLine" data-kind="${kind}">+ Thêm dòng</button></div>`;
}
function readLines(f,kind){
  return [...f.querySelectorAll('#lines tr')].map(tr=>({mat:tr.querySelector('.li-mat').value,qty:Math.round(num(tr.querySelector('.li-qty').value)),
    price:kind==='SO'?Math.round(num(tr.querySelector('.li-price').value)):undefined}));
}
function setErr(f,msg){ const e=f.querySelector('.err'); if(e){ e.innerHTML=msg; if(msg) e.scrollIntoView({block:'nearest'}); } }
function pickTable(rows,cols){
  if(!rows.length) return `<div class="tw"><div class="empty">Không có chứng từ nào đang chờ ở bước này.</div></div>`;
  return `<div class="tw"><table class="t"><thead><tr>${cols.map(c=>`<th class="${c.n?'num':''}">${c.h}</th>`).join('')}<th></th></tr></thead><tbody>${rows.map(r=>`<tr>${cols.map(c=>`<td class="${c.n?'num':''}">${c.f(r)}</td>`).join('')}<td>${r.__act||''}</td></tr>`).join('')}</tbody></table></div>`;
}

/* ============ P2P SCREENS ============ */
function scrPR(){
  return `<div class="wrap">${head('ME51N','Tạo đề nghị mua hàng','Thủ kho lập khi tồn kho thấp hơn mức dự trữ. Sau khi lưu, đề nghị chuyển đến Kế toán trưởng phê duyệt (ME54N).')}
  <form class="form panel" data-form="PR" data-calc="PR"><div class="err"></div>
    <div class="grid3"><label class="field"><span>Ngày đề nghị</span><input type="date" id="f-date" value="${today()}" required></label>
    <label class="field"><span>Ngày cần hàng</span><input type="date" id="f-need" value="${addDays(today(),7)}" required></label></div>
    <label class="field"><span>Lý do đề nghị</span><input id="f-reason" required maxlength="200" placeholder="Ví dụ: Tồn kho laptop dưới mức tối thiểu 10 cái, có đơn hàng dự kiến"></label>
    ${lineTable('PR',S.co)}
    <div class="form-foot"><div class="sum" id="f-sum"></div><button class="btn pri">Lưu và gửi duyệt</button></div></form></div>`;
}
function scrPO(){
  const c = calc(S.co);
  if(!S.param) return `<div class="wrap">${head('ME21N','Tạo đơn mua hàng','Chọn một đề nghị mua đã được duyệt để chuyển thành đơn mua hàng.')}
    ${pickTable(c.Q.prForPO.map(p=>Object.assign({},p,{__act:`<button class="btn sm pri" data-go="ME21N" data-p="${P({pr:p.id})}">Lập đơn mua</button>`})),
      [{h:'Số đề nghị',f:p=>docLink(S.co,p)},{h:'Ngày',f:p=>vd(p.date)},{h:'Lý do',f:p=>esc(p.reason)},{h:'Giá trị ước tính',n:1,f:p=>fm(valueOf(p))}])}</div>`;
  const pr = c.by[S.param.pr]; if(!pr) return `<div class="wrap"><div class="err">Không tìm thấy đề nghị mua.</div></div>`;
  const vs = okVens(S.co); const v0 = vs[0] || {c:''};
  const hid = vensOf(S.co).filter(v=>!vs.includes(v));
  return `<div class="wrap">${head('ME21N','Tạo đơn mua hàng','Tham chiếu đề nghị mua '+esc(pr.no)+'. So sánh báo giá các nhà cung cấp trước khi chọn. Ô có dấu ● lấy từ bảng giá ME11, còn lại là giá tham khảo.')}
  <div class="panel"><h2>Bảng báo giá nhà cung cấp (đơn giá chưa VAT)</h2><div class="tw"><table class="t"><thead><tr><th>Vật tư</th>${vs.map(v=>`<th class="num">${esc(v.c)}<br><span class="small">${v.terms} ngày</span></th>`).join('')}</tr></thead>
  <tbody>${pr.items.map(it=>`<tr><td>${esc(it.mat)} · ${esc(mat(it.mat).n)}</td>${vs.map(v=>{const q=priceOf(S.co,v.c,it.mat,today());return `<td class="num" title="${esc(q.src)}">${q.src.startsWith('ME11')?'● ':''}${fm(q.p)}</td>`;}).join('')}</tr>`).join('')}</tbody></table></div>
  ${hid.length?`<p class="small muted" style="margin-bottom:0">Không hiện ${hid.length} nhà cung cấp đang khóa hoặc chưa được Kế toán trưởng xác nhận (ZMDA): ${hid.map(v=>esc(v.c)).join(', ')}.</p>`:''}</div>
  <form class="form panel" data-form="PO" data-calc="PO" data-pr="${esc(pr.id)}"><div class="err"></div>
   <div class="grid3"><label class="field"><span>Nhà cung cấp</span><select id="f-vendor" data-chg="povendor">${vs.map(v=>`<option value="${v.c}">${v.c} · ${esc(v.n)}</option>`).join('')}</select></label>
   <label class="field"><span>Ngày đặt hàng</span><input type="date" id="f-date" value="${today()}" required></label>
   <label class="field"><span>Ngày giao dự kiến</span><input type="date" id="f-need" value="${esc(pr.need||addDays(today(),7))}" required></label></div>
   <div class="tw"><table class="t"><thead><tr><th>Hàng hóa</th><th class="num">Số lượng</th><th class="num">Đơn giá</th><th class="num">Thành tiền</th></tr></thead><tbody id="polines">
   ${pr.items.map((it,i)=>`<tr data-i="${i}" data-mat="${esc(it.mat)}" data-qty="${it.qty}"><td>${esc(it.mat)} · ${esc(mat(it.mat).n)}</td><td class="num">${it.qty}</td><td><input class="po-price num" type="number" min="0" step="1" value="${priceOf(S.co,v0.c,it.mat,today()).p}" aria-label="Đơn giá"></td><td class="num po-amt"></td></tr>`).join('')}
   </tbody></table></div>
   <label class="field"><span>Ghi chú gửi nhà cung cấp</span><input id="f-note" maxlength="200" placeholder="Điều kiện giao hàng, địa điểm nhận"></label>
   <div class="form-foot"><div class="sum" id="f-sum"></div><button class="btn pri">Lưu đơn mua hàng</button></div></form></div>`;
}
function scrGR(){
  const c = calc(S.co);
  if(!S.param) return `<div class="wrap">${head('MIGO','Nhập kho theo đơn mua','Chọn đơn mua đã được duyệt. Chỉ nhập kho số hàng thực nhận, đối chiếu với phiếu giao hàng của nhà cung cấp.')}
    ${pickTable(c.Q.poForGR.map(p=>Object.assign({},p,{__act:`<button class="btn sm pri" data-go="MIGO" data-p="${P({po:p.id})}">Nhập kho</button>`})),
      [{h:'Đơn mua',f:p=>docLink(S.co,p)},{h:'Nhà cung cấp',f:p=>esc(partnerOf(p))},{h:'Ngày giao dự kiến',f:p=>vd(p.need)},{h:'SL còn phải nhận',n:1,f:p=>sum(c.poOpen(p))}])}</div>`;
  const po = c.by[S.param.po]; if(!po) return `<div class="wrap"><div class="err">Không tìm thấy đơn mua.</div></div>`;
  const op = c.poOpen(po);
  return `<div class="wrap">${head('MIGO','Nhập kho theo đơn mua '+esc(po.no),'Nhà cung cấp: '+esc(partnerOf(po))+'. Hàng nhập kho được ghi nhận theo giá đơn mua (giá tạm tính) cho đến khi có hóa đơn.')}
  <form class="form panel" data-form="GR" data-po="${esc(po.id)}"><div class="err"></div>
   <div class="grid3"><label class="field"><span>Ngày nhập kho</span><input type="date" id="f-date" value="${today()}" required></label>
   <label class="field"><span>Số phiếu giao hàng của NCC</span><input id="f-dn" required maxlength="30" placeholder="Ví dụ: PGH-0451"></label>
   <label class="field"><span>Người giao hàng</span><input id="f-deliv" required maxlength="60"></label></div>
   <div class="tw"><table class="t"><thead><tr><th>Hàng hóa</th><th class="num">SL đặt</th><th class="num">Đã nhận</th><th class="num">Còn lại</th><th class="num">SL thực nhận</th></tr></thead><tbody>
   ${po.items.map((it,i)=>op[i]>0?`<tr class="gr-line" data-i="${i}"><td>${esc(it.mat)} · ${esc(mat(it.mat).n)}</td><td class="num">${it.qty}</td><td class="num">${it.qty-op[i]}</td><td class="num">${op[i]}</td><td><input class="gr-qty num" type="number" min="0" max="${op[i]}" step="1" value="${op[i]}" aria-label="Số lượng thực nhận"></td></tr>`:'').join('')}
   </tbody></table></div>
   <div class="form-foot"><span class="small muted">Bút toán: Nợ TK tồn kho của vật tư (152 hoặc 156) / Có TK 331 theo giá đơn mua.</span><button class="btn pri">Ghi sổ nhập kho</button></div></form></div>`;
}
function scrIV(){
  const c = calc(S.co);
  if(!S.param) return `<div class="wrap">${head('MIRO','Nhận & đối chiếu hóa đơn mua','Chọn đơn mua đã có hàng nhập kho nhưng chưa nhận hóa đơn. Hệ thống đối chiếu 3 bên: đơn mua – phiếu nhập – hóa đơn.')}
    ${pickTable(c.Q.poForIV.map(p=>Object.assign({},p,{__act:`<button class="btn sm pri" data-go="MIRO" data-p="${P({po:p.id})}">Nhập hóa đơn</button>`})),
      [{h:'Đơn mua',f:p=>docLink(S.co,p)},{h:'Nhà cung cấp',f:p=>esc(partnerOf(p))},{h:'SL đã nhập chưa có HĐ',n:1,f:p=>sum(c.poUninv(p))}])}</div>`;
  const po = c.by[S.param.po]; if(!po) return `<div class="wrap"><div class="err">Không tìm thấy đơn mua.</div></div>`;
  const un = c.poUninv(po);
  return `<div class="wrap">${head('MIRO','Hóa đơn mua theo đơn '+esc(po.no),'Nhập đúng số liệu trên hóa đơn GTGT của '+esc(partnerOf(po))+'. Chênh lệch giá vượt '+S.cfg.tol+'% so với đơn mua sẽ bị khóa thanh toán chờ Kế toán trưởng xem xét.')}
  <form class="form panel" data-form="IV" data-calc="IV" data-po="${esc(po.id)}"><div class="err"></div>
   <div class="grid3"><label class="field"><span>Ký hiệu hóa đơn</span><input id="f-sym" required maxlength="10" value="1C${YY}TAA"></label>
   <label class="field"><span>Số hóa đơn</span><input id="f-no" required maxlength="10" inputmode="numeric" placeholder="00001234"></label>
   <label class="field"><span>Ngày hóa đơn</span><input type="date" id="f-date" value="${today()}" required></label>
   <label class="field"><span>Tổng tiền thanh toán ghi trên hóa đơn</span><input id="f-gross" class="num" type="number" min="0" step="1" required></label></div>
   <div class="tw"><table class="t"><thead><tr><th>Hàng hóa</th><th class="num">SL đã nhập chưa HĐ</th><th class="num">SL trên HĐ</th><th class="num">Giá đơn mua</th><th class="num">Đơn giá trên HĐ</th><th class="num">Chênh lệch</th></tr></thead><tbody>
   ${po.items.map((it,i)=>un[i]>0?`<tr class="iv-line" data-i="${i}" data-po="${it.price}"><td>${esc(it.mat)} · ${esc(mat(it.mat).n)}</td><td class="num">${un[i]}</td><td><input class="iv-qty num" type="number" min="0" max="${un[i]}" step="1" value="${un[i]}" aria-label="Số lượng trên hóa đơn"></td><td class="num">${fm(it.price)}</td><td><input class="iv-price num" type="number" min="0" step="1" value="${it.price}" aria-label="Đơn giá trên hóa đơn"></td><td class="num iv-var"></td></tr>`:'').join('')}
   </tbody></table></div>
   <div class="form-foot"><div class="sum" id="f-sum"></div><button class="btn pri">Ghi sổ hóa đơn</button></div></form></div>`;
}
function scrPAY(){
  const c = calc(S.co);
  if(!S.param) return `<div class="wrap">${head('F-53','Đề nghị thanh toán nhà cung cấp','Chọn hóa đơn mua đã ghi sổ và không bị khóa. Phiếu chi chỉ được ghi sổ sau khi Kế toán trưởng duyệt.')}
    ${pickTable(c.Q.ivForPay.map(p=>Object.assign({},p,{__act:`<button class="btn sm pri" data-go="F-53" data-p="${P({iv:p.id})}">Lập đề nghị chi</button>`})),
      [{h:'Hóa đơn',f:p=>docLink(S.co,p)+` <span class="small muted">${esc(p.invSym)}/${esc(p.invNo)}</span>`},{h:'Nhà cung cấp',f:p=>esc(partnerOf(p))},{h:'Hạn thanh toán',f:p=>vd(p.due)+(p.due<today()?' <span class="chip c-rejected">Quá hạn</span>':'')},{h:'Còn phải trả',n:1,f:p=>fm(p.total-c.ivPaid(p)-c.ivPend(p))}])}</div>`;
  const iv = c.by[S.param.iv]; if(!iv) return `<div class="wrap"><div class="err">Không tìm thấy hóa đơn.</div></div>`;
  const rem = iv.total-c.ivPaid(iv)-c.ivPend(iv);
  return `<div class="wrap">${head('F-53','Đề nghị thanh toán hóa đơn '+esc(iv.invSym+'/'+iv.invNo),'Nhà cung cấp: '+esc(partnerOf(iv))+'. Hạn thanh toán '+vd(iv.due)+'.')}
  <form class="form panel" data-form="PAY" data-iv="${esc(iv.id)}"><div class="err"></div>
   <dl class="kv"><dt>Tổng hóa đơn</dt><dd class="mono">${fm(iv.total)}</dd><dt>Đã chi</dt><dd class="mono">${fm(c.ivPaid(iv))}</dd><dt>Đang chờ duyệt / chờ thủ quỹ chi</dt><dd class="mono">${fm(c.ivPend(iv))}</dd><dt>Còn được đề nghị</dt><dd class="mono"><b>${fm(rem)}</b></dd></dl>
   <div class="grid3"><label class="field"><span>Ngày đề nghị</span><input type="date" id="f-date" value="${today()}" required></label>
   <label class="field"><span>Hình thức</span><select id="f-acc"><option value="112">Ủy nhiệm chi – TK 112</option><option value="111">Phiếu chi tiền mặt – TK 111</option></select></label>
   <label class="field"><span>Số tiền</span><input id="f-amt" class="num" type="number" min="1" max="${Math.round(rem)}" step="1" value="${Math.round(rem)}" required></label></div>
   <label class="field"><span>Nội dung</span><input id="f-memo" required maxlength="200" value="Thanh toán hóa đơn ${esc(iv.invSym)} số ${esc(iv.invNo)} cho ${esc(iv.vendor)}"></label>
   <div class="form-foot"><span class="small muted">${S.cfg.bankClear!==false?'Ủy nhiệm chi: KTT duyệt → Nợ 331 / Có 113 (tiền đang chuyển), ngân hàng báo Nợ ngày làm việc kế tiếp, khớp ở FF67 thì Nợ 113 / Có 112 (cách tài khoản trung gian kiểu SAP; kế toán Việt Nam thường ghi Nợ 113 / Có 112 khi chuyển, Nợ 331 / Có 113 khi có giấy báo Nợ – xem ghi chú ở FF67). ':'Ủy nhiệm chi: KTT duyệt → Nợ 331 / Có 112. '}Tiền mặt: KTT duyệt → Thủ quỹ chi và xác nhận → Nợ 331 / Có 111.</span><button class="btn pri">Gửi duyệt chi</button></div></form></div>`;
}

/* ============ O2C SCREENS ============ */
function scrSO(){
  const c = calc(S.co);
  return `<div class="wrap">${head('VA01','Tạo đơn bán hàng','Hệ thống kiểm tra hạn mức tín dụng khi lưu. Đơn vượt hạn mức bị khóa và chuyển Kế toán trưởng xem xét (VKM3).')}
  <form class="form panel" data-form="SO" data-calc="SO"><div class="err"></div>
   <div class="grid3"><label class="field"><span>Khách hàng</span><select id="f-cust" data-chg="socust">${okCusts(S.co).map(x=>`<option value="${x.c}">${x.c} · ${esc(x.n)}</option>`).join('')}</select></label>
   <label class="field"><span>Số đơn đặt hàng của khách</span><input id="f-cpo" required maxlength="30" placeholder="Ví dụ: DH-BX-112"></label>
   <label class="field"><span>Ngày đơn hàng</span><input type="date" id="f-date" value="${today()}" required></label>
   <label class="field"><span>Ngày giao yêu cầu</span><input type="date" id="f-need" value="${addDays(today(),3)}" required></label></div>
   ${lineTable('SO',S.co)}
   <div class="note" id="f-credit"></div>
   <div class="form-foot"><div class="sum" id="f-sum"></div><button class="btn pri">Lưu đơn bán hàng</button></div></form></div>`;
}
function scrDL(){
  const c = calc(S.co);
  if(!S.param) return `<div class="wrap">${head('VL01N','Giao hàng & xuất kho','Chọn đơn bán đã xác nhận. Không được xuất quá số tồn kho thực tế.')}
    ${pickTable(c.Q.soForDL.map(p=>Object.assign({},p,{__act:`<button class="btn sm pri" data-go="VL01N" data-p="${P({so:p.id})}">Xuất kho</button>`})),
      [{h:'Đơn bán',f:p=>docLink(S.co,p)},{h:'Khách hàng',f:p=>esc(partnerOf(p))},{h:'Ngày giao yêu cầu',f:p=>vd(p.need)},{h:'SL còn phải giao',n:1,f:p=>sum(c.soOpen(p))}])}</div>`;
  const so = c.by[S.param.so]; if(!so) return `<div class="wrap"><div class="err">Không tìm thấy đơn bán.</div></div>`;
  const op = c.soOpen(so);
  return `<div class="wrap">${head('VL01N','Xuất kho cho đơn bán '+esc(so.no),'Khách hàng: '+esc(partnerOf(so))+'. Giá vốn tính theo bình quân gia quyền tại thời điểm xuất.')}
  <form class="form panel" data-form="DL" data-so="${esc(so.id)}"><div class="err"></div>
   <div class="grid3"><label class="field"><span>Ngày xuất kho</span><input type="date" id="f-date" value="${today()}" required></label>
   <label class="field"><span>Người nhận hàng</span><input id="f-recv" required maxlength="60"></label>
   <label class="field"><span>Phương tiện / biển số</span><input id="f-veh" maxlength="30" placeholder="79C-123.45"></label></div>
   <div class="tw"><table class="t"><thead><tr><th>Hàng hóa</th><th class="num">SL đặt</th><th class="num">Còn phải giao</th><th class="num">Tồn kho</th><th class="num">Giá vốn BQ</th><th class="num">SL thực xuất</th></tr></thead><tbody>
   ${so.items.map((it,i)=>op[i]>0?`<tr class="dl-line" data-i="${i}"><td>${esc(it.mat)} · ${esc(mat(it.mat).n)}</td><td class="num">${it.qty}</td><td class="num">${op[i]}</td><td class="num">${c.st[it.mat].q}</td><td class="num">${fm(c.st[it.mat].avg)}</td><td><input class="dl-qty num" type="number" min="0" step="1" value="${Math.max(0,Math.min(op[i],c.st[it.mat].q))}" aria-label="Số lượng thực xuất"></td></tr>`:'').join('')}
   </tbody></table></div>
   <div class="form-foot"><span class="small muted">Bút toán: Nợ TK 632 / Có TK tồn kho của vật tư (155 hoặc 156) theo giá vốn bình quân.</span><button class="btn pri">Ghi sổ xuất kho</button></div></form></div>`;
}
function scrBI(){
  const c = calc(S.co);
  if(!S.param) return `<div class="wrap">${head('VF01','Lập hóa đơn bán hàng','Hóa đơn chỉ lập cho hàng đã thực xuất kho, theo đơn giá đã thỏa thuận trên đơn bán.')}
    ${pickTable(c.Q.dlForBI.map(p=>Object.assign({},p,{__act:`<button class="btn sm pri" data-go="VF01" data-p="${P({dl:p.id})}">Lập hóa đơn</button>`})),
      [{h:'Phiếu xuất',f:p=>docLink(S.co,p)},{h:'Khách hàng',f:p=>esc(partnerOf(p))},{h:'Ngày xuất',f:p=>vd(p.date)},{h:'Số lượng',n:1,f:p=>sum(p.items,x=>x.qty)}])}</div>`;
  const dl = c.by[S.param.dl]; if(!dl) return `<div class="wrap"><div class="err">Không tìm thấy phiếu xuất.</div></div>`;
  const so = c.by[dl.so];
  const items = dl.items.map(x=>({line:x.line,mat:x.mat,qty:x.qty,price:so.items[x.line].price}));
  const net = sum(items,x=>x.qty*x.price), vat = Math.round(net*VATR());
  const nextNo = pad(Math.max(0,...c.T.BI.map(d=>d.seq||0))+1,8);
  return `<div class="wrap">${head('VF01','Hóa đơn GTGT cho phiếu xuất '+esc(dl.no),'Khách hàng: '+esc(partnerOf(dl))+'. Thuế suất GTGT 10%.')}
  <form class="form panel" data-form="BI" data-dl="${esc(dl.id)}"><div class="err"></div>
   <div class="grid3"><label class="field"><span>Ký hiệu</span><input readonly value="1C${YY}T${'ABCDEFGH'[COS.indexOf(S.co)]}A"></label>
   <label class="field"><span>Số hóa đơn (tự cấp)</span><input readonly value="${nextNo}"></label>
   <label class="field"><span>Ngày hóa đơn</span><input type="date" id="f-date" value="${today()}" required></label></div>
   <div class="tw"><table class="t"><thead><tr><th>Hàng hóa</th><th class="num">Số lượng</th><th class="num">Đơn giá</th><th class="num">Thành tiền</th></tr></thead><tbody>
   ${items.map(x=>`<tr><td>${esc(x.mat)} · ${esc(mat(x.mat).n)}</td><td class="num">${x.qty}</td><td class="num">${fm(x.price)}</td><td class="num">${fm(x.qty*x.price)}</td></tr>`).join('')}</tbody>
   <tfoot><tr><td colspan="3">Cộng tiền hàng</td><td class="num">${fm(net)}</td></tr><tr><td colspan="3">Thuế GTGT 10%</td><td class="num">${fm(vat)}</td></tr><tr><td colspan="3">Tổng thanh toán</td><td class="num">${fm(net+vat)}</td></tr></tfoot></table></div>
   <div class="form-foot"><span class="small muted">Bút toán: Nợ TK 131 / Có TK 5111, Có TK 33311.</span><button class="btn pri">Phát hành hóa đơn</button></div></form></div>`;
}
function scrRC(){
  const c = calc(S.co);
  if(!S.param) return `<div class="wrap">${head('F-28','Ghi nhận thu tiền khách hàng','Chọn hóa đơn bán còn phải thu. Phiếu thu chỉ ghi sổ sau khi Kế toán trưởng duyệt.')}
    ${pickTable(c.Q.biForRC.map(p=>Object.assign({},p,{__act:`<button class="btn sm pri" data-go="F-28" data-p="${P({bi:p.id})}">Ghi nhận thu</button>`})),
      [{h:'Hóa đơn',f:p=>docLink(S.co,p)+` <span class="small muted">${esc(p.invSym)}/${esc(p.invNo)}</span>`},{h:'Khách hàng',f:p=>esc(partnerOf(p))},{h:'Hạn thu',f:p=>vd(p.due)},{h:'Còn phải thu',n:1,f:p=>fm(p.total-c.biPaid(p)-c.biPend(p))}])}</div>`;
  const bi = c.by[S.param.bi]; if(!bi) return `<div class="wrap"><div class="err">Không tìm thấy hóa đơn.</div></div>`;
  const rem = bi.total-c.biPaid(bi)-c.biPend(bi);
  return `<div class="wrap">${head('F-28','Thu tiền hóa đơn '+esc(bi.invSym+'/'+bi.invNo),'Khách hàng: '+esc(partnerOf(bi))+'.')}
  <form class="form panel" data-form="RC" data-bi="${esc(bi.id)}"><div class="err"></div>
   <dl class="kv"><dt>Tổng hóa đơn</dt><dd class="mono">${fm(bi.total)}</dd><dt>Đã thu</dt><dd class="mono">${fm(c.biPaid(bi))}</dd><dt>Còn phải thu</dt><dd class="mono"><b>${fm(rem)}</b></dd></dl>
   <div class="grid3"><label class="field"><span>Ngày thu</span><input type="date" id="f-date" value="${today()}" required></label>
   <label class="field"><span>Hình thức</span><select id="f-acc"><option value="112">Giấy báo Có ngân hàng – TK 112</option><option value="111">Phiếu thu tiền mặt – TK 111</option></select></label>
   <label class="field"><span>Số tiền thực thu</span><input id="f-amt" class="num" type="number" min="1" max="${Math.round(rem)}" step="1" value="${Math.round(rem)}" required></label>
   <label class="field"><span>Số giấy báo Có / người nộp</span><input id="f-ref" required maxlength="40" placeholder="GBC 2026-0815"></label></div>
   <div class="form-foot"><span class="small muted">Chuyển khoản (đã có giấy báo Có): KTT duyệt → Nợ 112 / Có 131. Tiền mặt: KTT duyệt → Thủ quỹ thu và xác nhận → Nợ 111 / Có 131.</span><button class="btn pri">Gửi duyệt thu</button></div></form></div>`;
}

/* ============ APPROVAL INBOX ============ */
function scrInbox(tc){
  const c = calc(S.co); const types = TC[tc].ap || ['PR','PO','IV','SO','PAY','RC'];
  const rows = [].concat(...types.map(t=>c.Q.ap[t]));
  const why = d => ({PR:'Duyệt nhu cầu mua',PO:'Duyệt đơn mua & giá',IV:'Chênh lệch giá vượt dung sai',SO:'Vượt hạn mức tín dụng',PAY:'Duyệt chi tiền',RC:'Xác nhận đã thu tiền'})[d.type];
  return `<div class="wrap">${head(tc,TC[tc].t,'Mở từng chứng từ, kiểm tra thông tin và đối chiếu chứng từ gốc trước khi phê duyệt hoặc từ chối. Người lập không được tự phê duyệt.')}
  ${rows.length?`<div class="tw"><table class="t"><thead><tr><th>Loại</th><th>Số CT</th><th>Ngày</th><th>Đối tượng</th><th class="num">Giá trị</th><th>Lý do chờ</th><th>Người lập</th></tr></thead><tbody>
  ${rows.map(d=>`<tr class="click" data-go="DOC" data-p="${P({co:S.co,id:d.id})}"><td>${esc(TYPES[d.type].n)}</td><td class="mono">${esc(d.no)}</td><td>${vd(d.date)}</td><td>${esc(partnerOf(d))}</td><td class="num">${fm(valueOf(d))}</td><td>${chip(d)} <span class="small muted">${esc(why(d))}</span></td><td>${esc(nameOf(d.by))}</td></tr>`).join('')}</tbody></table></div>`
  :`<div class="tw"><div class="empty">Không có chứng từ nào chờ phê duyệt.</div></div>`}</div>`;
}

/* ============ LISTS ============ */
function scrList(tc){
  const c = calc(S.co); const types = TC[tc].list;
  const f = S.param&&S.param.f || 'all';
  let rows = c.L.filter(d=>types.includes(d.type)).slice().reverse();
  const sts = [...new Set(rows.map(d=>d.status))];
  if(f!=='all') rows = rows.filter(d=>d.status===f);
  return `<div class="wrap">${head(tc,TC[tc].t,'Bấm vào một dòng để xem chi tiết, mẫu chứng từ, luồng chứng từ và nhật ký phê duyệt.')}
  <div class="acts" style="display:flex;gap:6px;flex-wrap:wrap"><button class="btn sm ${f==='all'?'pri':''}" data-go="${tc}" data-p="${P({f:'all'})}">Tất cả</button>${sts.map(s=>`<button class="btn sm ${f===s?'pri':''}" data-go="${tc}" data-p="${P({f:s})}">${esc(stLabel({type:types.find(t=>c.L.some(d=>d.type===t&&d.status===s))||types[0],status:s}))}</button>`).join('')}</div>
  ${rows.length?`<div class="tw"><table class="t"><thead><tr><th>Số CT</th><th>Loại</th><th>Ngày</th><th>Đối tượng</th><th class="num">Giá trị</th><th>Trạng thái</th><th>Người lập</th></tr></thead><tbody>
  ${rows.map(d=>`<tr class="click" data-go="DOC" data-p="${P({co:S.co,id:d.id})}"><td class="mono">${esc(d.no)}</td><td>${esc(TYPES[d.type].n)}</td><td>${vd(d.date)}</td><td>${esc(partnerOf(d))}</td><td class="num">${fm(valueOf(d))}</td><td>${chip(d)}</td><td>${esc(nameOf(d.by))} <span class="small muted">${esc(d.role||'')}</span></td></tr>`).join('')}</tbody></table></div>`
  :`<div class="tw"><div class="empty">Chưa có chứng từ. Chứng từ được lập ở ${types.map(t=>`<code>${TYPES[t].tc}</code>`).join(', ')} sẽ hiện ở đây.</div></div>`}</div>`;
}

