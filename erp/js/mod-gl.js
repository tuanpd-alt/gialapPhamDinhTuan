"use strict";
/* ERP Lab – P3: sổ cái, kỳ kế toán, tiền và ngân hàng.
   FB50 bút toán tay, FBS1 trích trước tự đảo, FB08 đảo, FB03 tra cứu, FAGLL03 sổ cái theo tài khoản, ZSO sổ mẫu in,
   OB52 đóng/mở kỳ, FBCJ quỹ tiền mặt, ZKQ kiểm kê quỹ, FF67 sao kê ngân hàng, ZBRR đối chiếu ngân hàng, ZTU tạm ứng.
   Mọi ghi sổ do máy chủ thực hiện theo ngày làm việc của công ty; giao diện chỉ gửi dữ liệu nhập. */
(function(){
/* ---------- Tiện ích ---------- */
const md = co => Object.assign({org:[],periods:[],bank:[],state:{}}, mdOf(co)||{});
const actRole = () => S.isAdmin?S.role:'';
const ym = d => String(d||'').slice(0,7);
const pdOf = d => d.pdate||d.date;
const GRP = {'+':'Tất cả tài khoản','MM':'Tồn kho (152, 155, 156)','AR':'Phải thu (131)','AP':'Phải trả (331)','AA':'Tài sản cố định (211, 214)','GL':'Các tài khoản còn lại'};
const MONTHS = fy => Array.from({length:12},(_,i)=>fy+'-'+String(i+1).padStart(2,'0'));
const ymLabel = s => s ? s.slice(5,7)+'/'+s.slice(0,4) : '';
const accName = a => (S.acct&&S.acct[a]&&S.acct[a].n) || ACCS[a] || '';
// Tài khoản cho phép hạch toán tay: có cờ manual, không phải TK đối chiếu, không phải TK tiền
const manualAccs = () => Object.keys(S.acct||{}).filter(a=>{const x=S.acct[a];return x.man&&!x.r&&!['111','112','113'].includes(a);}).sort();
const ccList = () => md(S.co).org.filter(o=>o.k==='CC');
const ccNeed = a => !!(S.acct&&S.acct[a]&&S.acct[a].cc);
function isClosed(co,date,grp){ const y=+String(date).slice(0,4), p=+String(date).slice(5,7);
  return md(co).periods.some(x=>x.fy===y&&x.per===p&&(x.grp==='+'||x.grp===grp)); }
const accOpts = (sel,list) => `<option value="">– chọn tài khoản –</option>`+list.map(a=>`<option value="${a}" ${a===sel?'selected':''}>${a} · ${esc(accName(a))}${ccNeed(a)?' ◆':''}</option>`).join('');
const ccOpts = sel => `<option value="">–</option>`+ccList().map(o=>`<option value="${esc(o.c)}" ${o.c===sel?'selected':''}>${esc(o.c)} · ${esc(o.n)}</option>`).join('');
const closedNote = () => isClosed(S.co,today(),'GL') ? `<div class="note bad">Kỳ ${ymLabel(ym(today()))} đang <b>đóng</b> cho nhóm tài khoản sổ cái. Chứng từ lập được nhưng Kế toán trưởng sẽ không duyệt ghi sổ được cho đến khi mở kỳ (OB52) hoặc giảng viên chuyển ngày làm việc.</div>` : '';
function csvDownload(name, rows){
  const esc2 = v => { const s=String(v==null?'':v); return /[",;\n]/.test(s)?'"'+s.replace(/"/g,'""')+'"':s; };
  const blob = new Blob(['﻿'+rows.map(r=>r.map(esc2).join(',')).join('\r\n')],{type:'text/csv;charset=utf-8'});
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click();
  setTimeout(()=>{ URL.revokeObjectURL(a.href); a.remove(); },500);
}
// Dòng sổ cái của một công ty, kèm ngày ghi sổ
const gl = co => calc(co).lines.map(x=>({d:x.d,j:x.j,pd:pdOf(x.d)})).sort((a,b)=>String(a.pd+(a.d.at||'')).localeCompare(String(b.pd+(b.d.at||''))));

/* ---------- FB50 / FBS1: bút toán tổng hợp ---------- */
function jeRow(a,dr,cr,cc,memo){
  return `<tr><td><select class="gl-a w-mat" data-chg="glacc" aria-label="Tài khoản">${accOpts(a||'',manualAccs())}</select></td>
   <td><input class="gl-dr num" type="number" min="0" step="1" value="${dr||''}" aria-label="Nợ"></td>
   <td><input class="gl-cr num" type="number" min="0" step="1" value="${cr||''}" aria-label="Có"></td>
   <td><select class="gl-cc" aria-label="Trung tâm chi phí" ${ccNeed(a)?'':'disabled'}>${ccOpts(cc||'')}</select></td>
   <td><input class="gl-memo" maxlength="120" value="${esc(memo||'')}" aria-label="Diễn giải dòng"></td>
   <td><button type="button" class="btn sm" data-act="glDel" aria-label="Xóa dòng">✕</button></td></tr>`;
}
function scrJE(kind){
  const tc = kind==='acc'?'FBS1':'FB50';
  const rev = new Date(today()); rev.setMonth(rev.getMonth()+1); rev.setDate(1);
  const revS = rev.getFullYear()+'-'+String(rev.getMonth()+1).padStart(2,'0')+'-01';
  return `<div class="wrap">${head(tc,kind==='acc'?'Bút toán trích trước (tự đảo đầu kỳ sau)':'Lập bút toán tổng hợp',
     kind==='acc'?'Ghi nhận chi phí phải trả cuối kỳ (ví dụ tiền điện, lãi vay chưa có hóa đơn). Khi Kế toán trưởng duyệt, hệ thống ghi sổ và tự lập bút toán đảo vào ngày đầu kỳ sau ('+vd(revS)+' nếu duyệt trong kỳ này). Bút toán phải được duyệt trước khi sang kỳ mới; duyệt muộn bị chặn.'
       :'Bút toán tay chỉ dùng cho nghiệp vụ không có giao dịch phân hệ (trích trước, phân bổ, điều chỉnh). Không ghi được vào tài khoản công nợ, tồn kho, tiền; tài khoản có dấu ◆ bắt buộc trung tâm chi phí. Bút toán chờ Kế toán trưởng duyệt mới ghi sổ; <b>ngày ghi sổ là ngày làm việc lúc Kế toán trưởng duyệt</b>, không phải ngày lập.')}
  ${closedNote()}
  <form class="form panel" data-form="GLJE" data-kind="${kind}" data-calc="GLJE"><div class="err"></div>
   <div class="grid3"><label class="field"><span>Ngày chứng từ</span><input id="f-date" type="date" max="${today()}" value="${today()}" required></label>
   <label class="field" style="grid-column:span 2"><span>Diễn giải *</span><input id="f-memo" maxlength="200" required placeholder="${kind==='acc'?'Trích trước chi phí điện tháng '+ymLabel(ym(today())):'Nội dung nghiệp vụ, căn cứ chứng từ gốc'}"></label></div>
   <div class="tw"><table class="t"><thead><tr><th>Tài khoản</th><th class="num">Nợ</th><th class="num">Có</th><th>TTCP</th><th>Diễn giải dòng</th><th></th></tr></thead>
   <tbody id="gl-lines">${kind==='acc'?jeRow('6417','','','CC300','')+jeRow('335','','',''):jeRow()+jeRow()}</tbody></table></div>
   <div><button type="button" class="btn sm" data-act="glAdd">+ Thêm dòng</button></div>
   <div class="form-foot"><span id="f-sum" class="sum"></span><button class="btn pri">Lưu và trình duyệt</button></div></form></div>`;
}
function readJE(f){
  const lines=[]; let bad='';
  f.querySelectorAll('#gl-lines tr').forEach((tr,i)=>{
    const a=tr.querySelector('.gl-a').value, dr=Math.round(num(tr.querySelector('.gl-dr').value)), cr=Math.round(num(tr.querySelector('.gl-cr').value));
    const cc=tr.querySelector('.gl-cc').value, memo=tr.querySelector('.gl-memo').value.trim();
    if(!a&&!dr&&!cr) return;
    if(!a){ bad=bad||'Dòng '+(i+1)+' chưa chọn tài khoản.'; return; }
    if((dr>0)===(cr>0)){ bad=bad||'Dòng '+(i+1)+' (TK '+a+') phải ghi một bên Nợ hoặc Có.'; return; }
    if(ccNeed(a)&&!cc){ bad=bad||'TK '+a+' bắt buộc chọn trung tâm chi phí.'; return; }
    lines.push(Object.assign({a},dr?{dr}:{cr},cc?{cc}:{},memo?{memo}:{}));
  });
  return {lines,bad};
}

/* ---------- FB08: đảo bút toán ---------- */
function scrFB08(){
  const c=calc(S.co); const id=S.param&&S.param.id;
  const pendRev = new Set(c.T.JE.filter(x=>x.kind==='rev'&&x.status==='pending').map(x=>x.revOf));
  const alloc = d => c.T.BS.some(x=>x.ref===d.id&&x.kind==='clr'&&x.status==='posted'&&!x.revBy);
  const can8 = d => d.status==='posted'&&d.kind!=='rev'&&!d.auto&&!d.revBy&&!pendRev.has(d.id)&&(d.type==='JE'||(d.type==='BS'&&d.kind!=='doc'&&!alloc(d)));
  if(id){ const d=c.by[id];
    if(!d||!['JE','BS'].includes(d.type)) return `<div class="wrap">${head('FB08','Đảo bút toán','')}<div class="err">FB08 chỉ đảo bút toán tổng hợp (FB50, FBS1) và chứng từ ghi sổ theo sao kê (phí, lãi, tiền về chưa rõ). Chứng từ nghiệp vụ được điều chỉnh bằng giao dịch của phân hệ.</div></div>`;
    if(!can8(d)) return `<div class="wrap">${head('FB08','Đảo bút toán','')}<div class="err">Bút toán ${esc(d.no)} không đảo được: chưa ghi sổ, đã được đảo hoặc đang có đề nghị đảo.</div></div>`;
    return `<div class="wrap">${head('FB08','Đảo bút toán '+d.no,'Hệ thống lập bút toán đảo Nợ ↔ Có, ghi vào ngày làm việc '+vd(today())+' (kỳ '+ymLabel(ym(today()))+'). Sổ của kỳ gốc giữ nguyên; hai chứng từ liên kết hai chiều.')}
    ${closedNote()}
    <div class="panel"><h2>Bút toán gốc · ghi sổ ${vd(pdOf(d))}</h2>${jeTable(d)}</div>
    <form class="form panel" data-form="GLREV" data-id="${esc(d.id)}"><div class="err"></div>
     <label class="field"><span>Lý do đảo *</span><input id="f-reason" maxlength="200" required placeholder="Ví dụ: ghi nhầm tài khoản, chi phí đã được điều chỉnh"></label>
     <div class="form-foot"><span class="small muted">Bút toán đảo cũng phải được Kế toán trưởng duyệt.</span><button class="btn pri">Lập bút toán đảo</button></div></form></div>`; }
  const rows=c.T.JE.filter(d=>d.status==='posted'&&d.kind!=='rev').concat(c.T.BS.filter(d=>d.status==='posted'&&d.kind!=='doc')).slice().reverse();
  return `<div class="wrap">${head('FB08','Đảo bút toán tổng hợp','Chọn bút toán FB50/FBS1 hoặc chứng từ ghi sổ theo sao kê (phí, lãi, tiền về chưa rõ, phân bổ) cần đảo. Đảo chứng từ sao kê thì dòng sao kê mở lại để xử lý lại ở FF67. Khoản treo 3388 đã phân bổ phải đảo phần phân bổ trước.')}
  <div class="tw"><table class="t"><thead><tr><th>Số CT</th><th>Ngày ghi sổ</th><th>Diễn giải</th><th class="num">Số tiền</th><th>Trạng thái</th><th></th></tr></thead><tbody>
  ${rows.map(d=>`<tr><td>${docLink(S.co,d)}</td><td>${vd(pdOf(d))}</td><td>${esc(d.memo||'')}</td><td class="num">${fm(Math.abs(d.amount||0))}</td>
    <td>${d.revBy?`<span class="chip c-rejected">Đã đảo</span> ${docLink(S.co,{id:d.revBy,no:d.revNo||d.revBy})}`:pendRev.has(d.id)?'<span class="chip c-pending">Đang chờ duyệt đảo</span>':chip(d)}</td>
    <td>${can8(d)?`<button class="btn sm" data-go="FB08" data-p="${P({id:d.id})}">Đảo</button>`:''}</td></tr>`).join('')||'<tr><td colspan="6" class="muted">Chưa có bút toán tổng hợp nào đã ghi sổ.</td></tr>'}</tbody></table></div></div>`;
}

/* ---------- FB03: tra cứu chứng từ kế toán ---------- */
function scrFB03(){
  const c=calc(S.co); const q=((S.param&&S.param.q)||'').trim().toLowerCase(); const t=(S.param&&S.param.t)||'';
  const rows=c.L.filter(d=>Array.isArray(d.je)&&d.je.length&&d.status!=='rejected'&&(!t||d.type===t)&&(!q||[d.no,d.jeNo,d.memo,d.id].some(x=>String(x||'').toLowerCase().includes(q))))
    .sort((a,b)=>String(pdOf(b)+b.at).localeCompare(String(pdOf(a)+a.at)));
  return `<div class="wrap">${head('FB03','Hiển thị chứng từ kế toán','Tìm theo số chứng từ, số bút toán hoặc diễn giải; bấm vào dòng để mở chứng từ, bút toán và nhật ký phê duyệt.')}
  <form class="form panel" data-form="FB03" style="flex-direction:row;flex-wrap:wrap;gap:8px;align-items:flex-end">
   <label class="field" style="flex:1;min-width:200px"><span>Tìm</span><input id="f-q" value="${esc(q)}" placeholder="Số chứng từ, JE2026…, diễn giải"></label>
   <label class="field"><span>Loại</span><select id="f-t"><option value="">Tất cả</option>${Object.keys(TYPES).map(k=>`<option value="${k}" ${k===t?'selected':''}>${esc(TYPES[k].n)}</option>`).join('')}</select></label>
   <button class="btn pri">Tìm</button></form>
  <div class="tw"><table class="t"><thead><tr><th>Ngày ghi sổ</th><th>Số CT</th><th>Số bút toán</th><th>Loại</th><th>Diễn giải / đối tượng</th><th class="num">Tổng Nợ</th></tr></thead><tbody>
  ${rows.slice(0,300).map(d=>`<tr class="click" data-go="DOC" data-p="${P({co:S.co,id:d.id})}"><td>${vd(pdOf(d))}</td><td class="mono">${esc(d.no)}</td><td class="mono small">${esc(d.jeNo||'')}</td><td class="small">${esc(TYPES[d.type].n)}</td><td class="small">${esc(d.memo||partnerOf(d))}</td><td class="num">${fm(sum(d.je,j=>j.dr||0))}</td></tr>`).join('')||'<tr><td colspan="6" class="muted">Không có chứng từ phù hợp.</td></tr>'}</tbody></table></div></div>`;
}

/* ---------- FAGLL03: sổ cái theo tài khoản ---------- */
function glQuery(co,p){
  const c=calc(co); const a=p.acc; const from=p.from||ym(today()).slice(0,4)+'-01', to=p.to||ym(today());
  const L=gl(co).filter(x=>x.j.a===a&&(!p.partner||x.j.p===p.partner)&&(!p.cc||x.j.cc===p.cc));
  const open=(p.partner||p.cc?0:(c.acc[a]?c.acc[a].o:0))+sum(L.filter(x=>ym(x.pd)<from),x=>(x.j.dr||0)-(x.j.cr||0));
  const rows=L.filter(x=>ym(x.pd)>=from&&ym(x.pd)<=to); let run=open;
  rows.forEach(x=>{ run+=(x.j.dr||0)-(x.j.cr||0); x.run=run; });
  return {a,from,to,open,rows,close:run,dr:sum(rows,x=>x.j.dr||0),cr:sum(rows,x=>x.j.cr||0)};
}
function periodPick(p,tc){
  const fy=+(ym(today()).slice(0,4)); const opts=sel=>[fy-1,fy,fy+1].flatMap(MONTHS).map(m=>`<option value="${m}" ${m===sel?'selected':''}>${ymLabel(m)}</option>`).join('');
  return `<label class="field"><span>Từ kỳ</span><select id="f-from">${opts(p.from||fy+'-01')}</select></label><label class="field"><span>Đến kỳ</span><select id="f-to">${opts(p.to||ym(today()))}</select></label>`;
}
function scrFAGLL03(){
  const p=Object.assign({acc:'112'},S.param||{}); const used=[...new Set(calc(S.co).lines.map(x=>x.j.a).concat(Object.keys(calc(S.co).acc).filter(a=>calc(S.co).acc[a].o)))].sort();
  const r=glQuery(S.co,p); const recon=S.acct&&S.acct[p.acc]&&S.acct[p.acc].r;
  const partners=[...new Set(calc(S.co).lines.filter(x=>x.j.a===p.acc&&x.j.p).map(x=>x.j.p))].sort();
  return `<div class="wrap">${head('FAGLL03','Sổ cái theo tài khoản','Liệt kê từng dòng bút toán của một tài khoản theo ngày ghi sổ, có số dư lũy kế. Bấm vào dòng để mở chứng từ gốc.',
     `<button class="btn sm" data-act="glCsv">Xuất CSV</button>`)}
  <form class="form panel" data-form="FAGL" style="flex-direction:row;flex-wrap:wrap;gap:8px;align-items:flex-end">
   <label class="field" style="min-width:240px"><span>Tài khoản</span><select id="f-acc">${used.map(a=>`<option value="${a}" ${a===p.acc?'selected':''}>${a} · ${esc(accName(a))}</option>`).join('')}</select></label>
   ${periodPick(p)}
   ${recon||partners.length?`<label class="field"><span>Đối tượng</span><select id="f-par"><option value="">Tất cả</option>${partners.map(x=>`<option ${x===p.partner?'selected':''}>${esc(x)}</option>`).join('')}</select></label>`:''}
   ${ccNeed(p.acc)?`<label class="field"><span>Trung tâm chi phí</span><select id="f-cc">${ccOpts(p.cc||'')}</select></label>`:''}
   <button class="btn pri">Xem</button></form>
  <div class="tw"><table class="t" id="gl-tbl"><thead><tr><th>Ngày GS</th><th>Số CT</th><th>Số bút toán</th><th>Diễn giải</th><th>Đối tượng</th><th>TTCP</th><th class="num">Nợ</th><th class="num">Có</th><th class="num">Số dư</th></tr></thead><tbody>
   <tr><td colspan="8"><i>Số dư đầu kỳ ${ymLabel(r.from)}${p.partner||p.cc?' (theo bộ lọc)':''}</i></td><td class="num">${fm(r.open)}</td></tr>
   ${r.rows.map(x=>`<tr class="click" data-go="DOC" data-p="${P({co:S.co,id:x.d.id})}"><td>${vd(x.pd)}</td><td class="mono">${esc(x.d.no)}</td><td class="mono small">${esc(x.d.jeNo||'')}</td><td class="small">${esc(x.j.memo||x.d.memo||TYPES[x.d.type].n)}</td><td class="small">${esc(x.j.p||x.j.mat||'')}</td><td class="small mono">${esc(x.j.cc||'')}</td><td class="num">${x.j.dr?fm(x.j.dr):''}</td><td class="num">${x.j.cr?fm(x.j.cr):''}</td><td class="num">${fm(x.run)}</td></tr>`).join('')}</tbody>
   <tfoot><tr><td colspan="6">Cộng phát sinh ${ymLabel(r.from)} – ${ymLabel(r.to)} · Số dư cuối kỳ</td><td class="num">${fm(r.dr)}</td><td class="num">${fm(r.cr)}</td><td class="num">${fm(r.close)}</td></tr></tfoot></table></div></div>`;
}

/* ---------- F.01 theo kỳ (thay màn hình bản P1) ---------- */
function scrTBp(){
  const p=S.param||{}; const c=calc(S.co); const from=p.from||ym(today()).slice(0,4)+'-01', to=p.to||ym(today());
  const L=gl(S.co); const t={od:0,oc:0,dr:0,cr:0,cd:0,cc:0};
  const accs=[...new Set(Object.keys(c.acc).filter(a=>c.acc[a].o).concat(L.map(x=>x.j.a)))].sort();
  const rows=accs.map(a=>{ const o=(c.acc[a]?c.acc[a].o:0)+sum(L.filter(x=>x.j.a===a&&ym(x.pd)<from),x=>(x.j.dr||0)-(x.j.cr||0));
    const M=L.filter(x=>x.j.a===a&&ym(x.pd)>=from&&ym(x.pd)<=to); const dr=sum(M,x=>x.j.dr||0), cr=sum(M,x=>x.j.cr||0); const cl=o+dr-cr;
    const r={a,od:o>0?o:0,oc:o<0?-o:0,dr,cr,cd:cl>0?cl:0,cc:cl<0?-cl:0}; Object.keys(t).forEach(k=>t[k]+=r[k]); return r; }).filter(r=>r.od||r.oc||r.dr||r.cr||r.cd||r.cc);
  const ok=Math.abs(t.dr-t.cr)<1&&Math.abs(t.cd-t.cc)<1&&Math.abs(t.od-t.oc)<1;
  return `<div class="wrap">${head('F.01','Bảng cân đối số phát sinh theo kỳ','Số dư đầu kỳ, phát sinh trong khoảng kỳ chọn và số dư cuối kỳ, tính theo ngày ghi sổ.',`<button class="btn sm" data-act="tbCsv">Xuất CSV</button>`)}
  <form class="form panel" data-form="TBP" style="flex-direction:row;flex-wrap:wrap;gap:8px;align-items:flex-end">${periodPick({from,to})}<button class="btn pri">Xem</button></form>
  <div class="note ${ok?'ok':'bad'}">${ok?'Tổng dư đầu, tổng phát sinh và tổng dư cuối đều cân Nợ – Có.':'<b>Bảng không cân.</b> Kiểm tra lại bút toán.'}</div>
  <div class="tw"><table class="t"><thead><tr><th>TK</th><th>Tên tài khoản</th><th class="num">Dư Nợ đầu kỳ</th><th class="num">Dư Có đầu kỳ</th><th class="num">PS Nợ</th><th class="num">PS Có</th><th class="num">Dư Nợ cuối kỳ</th><th class="num">Dư Có cuối kỳ</th></tr></thead><tbody>
  ${rows.map(r=>`<tr class="click" data-go="FAGLL03" data-p="${P({acc:r.a,from,to})}"><td class="mono">${r.a}</td><td>${esc(accName(r.a))}</td>${['od','oc','dr','cr','cd','cc'].map(k=>`<td class="num">${r[k]?fm(r[k]):''}</td>`).join('')}</tr>`).join('')}</tbody>
  <tfoot><tr><td colspan="2">Cộng</td>${['od','oc','dr','cr','cd','cc'].map(k=>`<td class="num">${fm(t[k])}</td>`).join('')}</tr></tfoot></table></div></div>`;
}

/* ---------- ZSO: sổ kế toán mẫu (in) ---------- */
function scrZSO(){
  const p=Object.assign({k:'nkc',acc:'111'},S.param||{}); const from=p.from||ym(today()), to=p.to||ym(today());
  const L=gl(S.co).filter(x=>ym(x.pd)>=from&&ym(x.pd)<=to);
  const hdr=(t,mau)=>`<div class="v-head"><div><b>${esc(coName(S.co))}</b><br>Địa chỉ: Nha Trang, Khánh Hòa</div><div style="text-align:right">Mẫu số ${mau}<br><span class="small">(tham khảo – CẦN GIẢNG VIÊN KIỂM TRA mẫu theo TT 99/2025/TT-BTC)</span></div></div>
    <div class="v-title">${t}</div><div class="v-sub">Từ kỳ ${ymLabel(from)} đến kỳ ${ymLabel(to)} · Đơn vị tính: đồng</div>`;
  let body='';
  if(p.k==='nkc'){
    body=hdr('SỔ NHẬT KÝ CHUNG','S03a-DN')+`<table class="t"><thead><tr><th>Ngày GS</th><th>Số hiệu CT</th><th>Ngày CT</th><th>Diễn giải</th><th>STT dòng</th><th>TK</th><th class="num">Nợ</th><th class="num">Có</th></tr></thead><tbody>
    ${L.map((x,i)=>`<tr><td>${vd(x.pd)}</td><td class="mono">${esc(x.d.no)}</td><td>${vd(x.d.date)}</td><td class="small">${esc(x.j.memo||x.d.memo||TYPES[x.d.type].n)}${x.j.p?' – '+esc(x.j.p):''}</td><td class="num">${i+1}</td><td class="mono">${esc(x.j.a)}</td><td class="num">${x.j.dr?fm(x.j.dr):''}</td><td class="num">${x.j.cr?fm(x.j.cr):''}</td></tr>`).join('')}</tbody>
    <tfoot><tr><td colspan="6">Cộng chuyển sang trang sau / Cộng cuối kỳ</td><td class="num">${fm(sum(L,x=>x.j.dr||0))}</td><td class="num">${fm(sum(L,x=>x.j.cr||0))}</td></tr></tfoot></table>`;
  } else {
    const r=glQuery(S.co,{acc:p.acc,from,to}); const by={}; gl(S.co).forEach(x=>{ (by[x.d.id+'|'+x.pd]=by[x.d.id+'|'+x.pd]||[]).push(x); });
    const contra=x=>[...new Set((by[x.d.id+'|'+x.pd]||[]).filter(y=>y.j.a!==p.acc&&((x.j.dr&&y.j.cr)||(x.j.cr&&y.j.dr))).map(y=>y.j.a))].join(', ');
    body=hdr('SỔ CÁI','S03b-DN')+`<p style="margin:4px 0">Tên tài khoản: <b>${esc(accName(p.acc))}</b> · Số hiệu: <b>${esc(p.acc)}</b></p>
    <table class="t"><thead><tr><th>Ngày GS</th><th>Số hiệu CT</th><th>Ngày CT</th><th>Diễn giải</th><th>TK đối ứng</th><th class="num">Nợ</th><th class="num">Có</th></tr></thead><tbody>
    <tr><td colspan="5"><b>Số dư đầu kỳ</b></td><td class="num">${r.open>0?fm(r.open):''}</td><td class="num">${r.open<0?fm(-r.open):''}</td></tr>
    ${r.rows.map(x=>`<tr><td>${vd(x.pd)}</td><td class="mono">${esc(x.d.no)}</td><td>${vd(x.d.date)}</td><td class="small">${esc(x.j.memo||x.d.memo||TYPES[x.d.type].n)}${x.j.p?' – '+esc(x.j.p):''}</td><td class="mono small">${esc(contra(x))}</td><td class="num">${x.j.dr?fm(x.j.dr):''}</td><td class="num">${x.j.cr?fm(x.j.cr):''}</td></tr>`).join('')}</tbody>
    <tfoot><tr><td colspan="5">Cộng số phát sinh</td><td class="num">${fm(r.dr)}</td><td class="num">${fm(r.cr)}</td></tr>
    <tr><td colspan="5">Số dư cuối kỳ</td><td class="num">${r.close>0?fm(r.close):''}</td><td class="num">${r.close<0?fm(-r.close):''}</td></tr></tfoot></table>`;
  }
  const accs=[...new Set(calc(S.co).lines.map(x=>x.j.a))].sort();
  return `<div class="wrap">${head('ZSO','Sổ kế toán theo mẫu','Hình thức Nhật ký chung: Sổ Nhật ký chung và Sổ Cái từng tài khoản, lập từ bút toán đã ghi sổ. Dùng nút In để in hoặc lưu PDF.',`<button class="btn sm pri" data-act="print">In sổ</button>`)}
  <form class="form panel noprint" data-form="ZSO" style="flex-direction:row;flex-wrap:wrap;gap:8px;align-items:flex-end">
   <label class="field"><span>Sổ</span><select id="f-k"><option value="nkc" ${p.k==='nkc'?'selected':''}>Sổ Nhật ký chung</option><option value="sc" ${p.k==='sc'?'selected':''}>Sổ Cái</option></select></label>
   <label class="field"><span>Tài khoản (Sổ Cái)</span><select id="f-acc">${accs.map(a=>`<option value="${a}" ${a===p.acc?'selected':''}>${a} · ${esc(accName(a))}</option>`).join('')}</select></label>
   ${periodPick({from,to})}<button class="btn pri">Lập sổ</button></form>
  <div class="voucher printable">${body}
   <div class="signs"><div><b>Người ghi sổ</b><div class="sg none">(Ký, họ tên)</div></div><div><b>Kế toán trưởng</b><div class="sg none">(Ký, họ tên)</div></div><div><b>Giám đốc</b><div class="sg none">(Ký, họ tên, đóng dấu)</div></div></div></div></div>`;
}

/* ---------- OB52: đóng / mở kỳ ---------- */
function scrOB52(){
  const fy=+((S.param&&S.param.fy)||ym(today()).slice(0,4)); const P_=md(S.co).periods; const canA=can('OB52','A');
  const isC=(m,g)=>P_.some(x=>x.fy===fy&&x.per===m&&x.grp===g);
  const cur=ym(today());
  return `<div class="wrap">${head('OB52','Đóng / mở kỳ kế toán','Đóng kỳ theo nhóm tài khoản: khi đóng, mọi bút toán có ngày ghi sổ trong kỳ đó vào nhóm tài khoản đó đều bị chặn. Đóng "Tất cả" là khóa sổ toàn bộ kỳ. Muốn điều chỉnh số liệu kỳ đã khóa, lập bút toán đảo hoặc điều chỉnh ở kỳ đang mở.',
     `<button class="btn sm" data-go="OB52" data-p="${P({fy:fy-1})}">← ${fy-1}</button><button class="btn sm" data-go="OB52" data-p="${P({fy:fy+1})}">${fy+1} →</button>`)}
  ${canA?'':'<div class="note">Chỉ Kế toán trưởng được đóng, mở kỳ. Bạn đang xem trạng thái.</div>'}
  <div class="tw"><table class="t matrix"><thead><tr><th>Kỳ ${fy}</th>${Object.keys(GRP).map(g=>`<th>${esc(GRP[g])}</th>`).join('')}</tr></thead><tbody>
  ${MONTHS(fy).map((m,i)=>`<tr${m===cur?' style="background:var(--hl,rgba(255,200,0,.08))"':''}><td><b>${ymLabel(m)}</b>${m===cur?' <span class="chip c-info">ngày làm việc</span>':''}</td>${Object.keys(GRP).map(g=>{const cl=isC(i+1,g);
    return `<td>${cl?'<span class="chip c-rejected">Đã đóng</span>':'<span class="chip c-approved">Mở</span>'}${canA?` <button class="btn sm" data-act="period" data-fy="${fy}" data-per="${i+1}" data-grp="${g}" data-close="${cl?0:1}">${cl?'Mở':'Đóng'}</button>`:''}</td>`;}).join('')}</tr>`).join('')}</tbody></table></div>
  <p class="small muted">Thứ tự thường gặp khi khóa sổ tháng: đóng Kho → Phải trả, Phải thu → Tài sản → kết chuyển (P10) → đóng Tất cả.</p></div>`;
}

/* ---------- FBCJ: quỹ tiền mặt ---------- */
function cashBook(co){ const c=calc(co); const L=gl(co).filter(x=>x.j.a==='111'); let run=c.acc['111']?c.acc['111'].o:0; const open=run;
  L.forEach(x=>{ run+=(x.j.dr||0)-(x.j.cr||0); x.run=run; }); return {open,L,close:run}; }
const CJDIR = {out:'Phiếu chi',in:'Phiếu thu',wd:'Rút tiền gửi về quỹ',dep:'Nộp tiền mặt vào ngân hàng'};
// Chứng từ KTT đã duyệt, chờ Thủ quỹ thu/chi thực tế rồi xác nhận (RV-11)
function cashQueue(c){
  return [].concat(c.T.PAY.filter(d=>d.status==='approved'&&d.acc==='111'), c.T.RC.filter(d=>d.status==='approved'&&d.acc==='111'),
    c.T.CJ.filter(d=>d.status==='approved'), c.T.ADV.filter(d=>d.status==='approved'), c.T.ADS.filter(d=>d.status==='approved'));
}
function cashDir(d){ if(d.type==='PAY') return ['Chi',d.amount]; if(d.type==='RC') return ['Thu',d.amount]; if(d.type==='ADV') return ['Chi',d.amount];
  if(d.type==='ADS') return d.ret>0?['Thu',d.ret]:['Chi',-d.ret]; return [['in','wd'].includes(d.dir)?'Thu':'Chi',d.amount]; }
function scrFBCJ(){
  const c=calc(S.co); const cb=cashBook(S.co); const canC=can('FBCJ','C'); const canT=can('ZTQ','C');
  const q=cashQueue(c); const pend=c.T.CJ.filter(d=>d.status==='pending');
  const accs=manualAccs();
  return `<div class="wrap">${head('FBCJ','Sổ quỹ tiền mặt – phiếu thu, phiếu chi','Kế toán lập phiếu thu, phiếu chi; Kế toán trưởng duyệt; Thủ quỹ thu, chi tiền thực tế rồi xác nhận mới ghi sổ TK 111. Thủ quỹ không tự lập phiếu. Tồn quỹ không được âm. Thu nợ khách hàng dùng F-28, chi trả nhà cung cấp dùng F-53 (không ghi thẳng TK 131, 331 ở đây).')}
  <div class="kpis"><div class="kpi"><span>Tồn quỹ theo sổ</span><b class="mono">${fm(cb.close)}</b></div><div class="kpi"><span>Phiếu chờ KTT duyệt</span><b>${pend.length}</b></div><div class="kpi"><span>Chờ thủ quỹ thu, chi</span><b>${q.length}</b></div></div>
  ${closedNote()}
  ${canT?`<div class="panel" style="border-color:var(--warn)"><h2>Chờ thủ quỹ thu, chi</h2>
   <p class="small muted" style="margin:0 0 8px">Chỉ bấm xác nhận sau khi đã đếm và giao, nhận tiền thực tế. Không thu, chi được (người nhận không đến, sai số tiền) thì ghi lý do và bấm Trả lại; chứng từ chuyển sang Từ chối, không ghi sổ. Người đã duyệt chứng từ không tự xác nhận thu, chi. Hệ thống ghi sổ TK 111 vào ngày làm việc ${vd(today())} và ghi tên bạn vào ô chữ ký Thủ quỹ.</p>
   ${q.length?`<div class="tw"><table class="t"><thead><tr><th>Chứng từ</th><th>Loại</th><th>Người nộp / nhận</th><th>Nội dung</th><th>Thu/Chi</th><th class="num">Số tiền</th><th></th></tr></thead><tbody>${q.map(d=>{const [k,a]=cashDir(d);
     return `<tr><td>${docLink(S.co,d)}</td><td class="small">${esc(d.type==='CJ'?CJDIR[d.dir]:TYPES[d.type].n)}</td><td>${esc(partnerOf(d))}</td><td class="small">${esc(d.reason||d.purpose||d.memo||'')}</td><td>${k}</td><td class="num">${fm(a)}</td>
      <td style="white-space:nowrap"><button class="btn sm pri" data-act="cashOk" data-id="${esc(d.id)}">${k==='Thu'?'Đã thu tiền':'Đã chi tiền'}</button>
       <input id="rt-${esc(d.id)}" placeholder="Lý do trả lại" maxlength="150" style="width:130px" aria-label="Lý do trả lại"> <button class="btn sm" data-act="cashBack" data-id="${esc(d.id)}">Trả lại</button></td></tr>`;}).join('')}</tbody></table></div>`:'<p class="small muted">Không có chứng từ chờ thu, chi.</p>'}</div>`:''}
  ${canC?`<form class="form panel" data-form="CJ" data-calc="CJ"><div class="err"></div><h2 style="margin:0">Lập phiếu</h2>
   <div class="grid3"><label class="field"><span>Loại phiếu</span><select id="f-dir" data-chg="cjdir">${Object.keys(CJDIR).map(k=>`<option value="${k}">${CJDIR[k]}</option>`).join('')}</select></label>
   <label class="field"><span>Ngày</span><input id="f-date" type="date" max="${today()}" value="${today()}" required></label>
   <label class="field"><span>Số tiền *</span><input id="f-amt" class="num" type="number" min="1" step="1" required></label>
   <label class="field cj-acc"><span>TK đối ứng *</span><select id="f-acc" data-chg="cjacc">${accOpts('',accs)}</select></label>
   <label class="field cj-acc"><span>Trung tâm chi phí</span><select id="f-cc" disabled>${ccOpts('')}</select></label>
   <label class="field"><span>Người nộp / người nhận *</span><input id="f-person" maxlength="80" required></label>
   <label class="field" style="grid-column:1/-1"><span>Lý do *</span><input id="f-reason" maxlength="200" required></label></div>
   <p class="small muted cj-bank" hidden>Rút tiền gửi: Nợ 111 / Có 112 khi Thủ quỹ nhận tiền. Nộp tiền mặt: Nợ 113 / Có 111 khi Thủ quỹ nộp; ngân hàng báo Có vào ngày làm việc kế tiếp, khớp ở FF67 (Nợ 112 / Có 113).</p>
   <div class="form-foot"><span id="f-sum" class="sum"></span><button class="btn pri">Lưu và trình duyệt</button></div></form>`:''}
  <div><h3 class="sec-title">Sổ quỹ tiền mặt (TK 111)</h3><div class="tw"><table class="t"><thead><tr><th>Ngày GS</th><th>Số CT</th><th>Diễn giải</th><th class="num">Thu</th><th class="num">Chi</th><th class="num">Tồn</th></tr></thead><tbody>
   <tr><td colspan="5"><i>Tồn đầu kỳ</i></td><td class="num">${fm(cb.open)}</td></tr>
   ${cb.L.map(x=>`<tr class="click" data-go="DOC" data-p="${P({co:S.co,id:x.d.id})}"><td>${vd(x.pd)}</td><td class="mono">${esc(x.d.no)}</td><td class="small">${esc(x.d.reason||x.d.memo||TYPES[x.d.type].n)}${x.d.person?' – '+esc(x.d.person):''}</td><td class="num">${x.j.dr?fm(x.j.dr):''}</td><td class="num">${x.j.cr?fm(x.j.cr):''}</td><td class="num">${fm(x.run)}</td></tr>`).join('')}</tbody></table></div></div>
  ${pend.length?`<div><h3 class="sec-title">Phiếu chờ Kế toán trưởng duyệt</h3><div class="tw"><table class="t"><tbody>${pend.map(d=>`<tr class="click" data-go="DOC" data-p="${P({co:S.co,id:d.id})}"><td class="mono">${esc(d.no)}</td><td>${esc(CJDIR[d.dir]||d.dir)}</td><td>${esc(d.reason)}</td><td class="num">${fm(d.amount)}</td><td>${chip(d)}</td></tr>`).join('')}</tbody></table></div></div>`:''}</div>`;
}

/* ---------- ZKQ: kiểm kê quỹ ---------- */
function scrZKQ(){
  const c=calc(S.co); const cb=cashBook(S.co); const rows=c.T.CNT.slice().reverse(); const canC=can('ZKQ','C');
  return `<div class="wrap">${head('ZKQ','Kiểm kê quỹ tiền mặt','Ban kiểm kê đếm tiền thực tế (số đếm do giảng viên cài trong SPRO, sinh viên không xem trước) và so với tồn quỹ theo sổ. Chênh lệch thiếu ghi Nợ 1381, thừa ghi Có 3381 sau khi Kế toán trưởng duyệt; xử lý trách nhiệm ở kỳ sau.')}
  <div class="kpis"><div class="kpi"><span>Tồn quỹ theo sổ</span><b class="mono">${fm(cb.close)}</b></div></div>
  ${canC?`<form class="form panel" data-form="CNT"><div class="err"></div>
   <div class="grid3"><label class="field"><span>Ngày kiểm kê</span><input id="f-date" type="date" max="${today()}" value="${today()}" required></label>
   <label class="field" style="grid-column:span 2"><span>Thành phần ban kiểm kê *</span><input id="f-members" maxlength="200" required placeholder="Thủ quỹ, Kế toán trưởng, Kiểm toán nội bộ"></label>
   <label class="field" style="grid-column:1/-1"><span>Nguyên nhân chênh lệch (nếu biết)</span><input id="f-reason" maxlength="200"></label></div>
   <div class="form-foot"><span class="small muted">Không lập được khi còn phiếu thu, phiếu chi chờ duyệt.</span><button class="btn pri">Lập biên bản kiểm kê</button></div></form>`:''}
  <div class="tw"><table class="t"><thead><tr><th>Số biên bản</th><th>Ngày</th><th class="num">Theo sổ</th><th class="num">Thực tế</th><th class="num">Chênh lệch</th><th>Trạng thái</th></tr></thead><tbody>
  ${rows.map(d=>`<tr class="click" data-go="DOC" data-p="${P({co:S.co,id:d.id})}"><td class="mono">${esc(d.no)}</td><td>${vd(d.date)}</td><td class="num">${fm(d.book)}</td><td class="num">${fm(d.counted)}</td><td class="num" style="color:${d.diff?'var(--bad)':'inherit'}">${fm(d.diff)}</td><td>${chip(d)}</td></tr>`).join('')||'<tr><td colspan="6" class="muted">Chưa có biên bản kiểm kê.</td></tr>'}</tbody></table></div></div>`;
}

/* ---------- FF67: sao kê ngân hàng ---------- */
const KIND = {doc:'Chi/thu theo chứng từ',fee:'Phí ngân hàng',int:'Lãi tiền gửi',unk:'Tiền về chưa rõ nội dung'};
function stmtOpen(co){ const c=calc(co); const ob=(c.T.OB[0]&&c.T.OB[0].je||[]).filter(j=>j.a==='112'); return sum(ob,j=>(j.dr||0)-(j.cr||0)); }
function scrFF67(){
  const B=md(S.co).bank; const canC=can('FF67','C'); const open=stmtOpen(S.co); let run=open;
  const rows=B.map(b=>{ run+=+b.amt; return Object.assign({run},b); });
  const c=calc(S.co); const bis=biOpen(c);
  const susp=c.T.BS.filter(d=>d.kind==='unk'&&!d.bi&&d.status==='posted'&&!d.revBy).map(d=>({d,rem:Math.abs(d.amount)-sum(c.T.BS.filter(x=>x.ref===d.id&&x.kind==='clr'&&x.status==='posted'&&!x.revBy),x=>+x.alloc||0)})).filter(x=>x.rem>0.5);
  return `<div class="wrap">${head('FF67','Sao kê ngân hàng – xử lý từng dòng','Ngân hàng hạch toán chi, thu chuyển khoản vào ngày làm việc kế tiếp sau ngày ghi sổ, đồng thời báo phí, lãi và các khoản khách chuyển chưa rõ nội dung. Mỗi dòng sao kê phải được xử lý để ghi vào TK 112.',
     `<button class="btn sm" data-act="bankRefresh">Nhận sao kê đến ngày ${vd(today())}</button>`)}
  ${closedNote()}
  <div class="kpis"><div class="kpi"><span>Số dư sao kê</span><b class="mono">${fm(run)}</b></div><div class="kpi"><span>Sổ TK 112</span><b class="mono">${fm(calc(S.co).bal('112'))}</b></div><div class="kpi"><span>Dòng chưa xử lý</span><b>${B.filter(b=>b.st==='open').length}</b></div><div class="kpi"><span>TK 113 tiền đang chuyển</span><b class="mono">${fm(calc(S.co).bal('113'))}</b></div></div>
  <div class="tw"><table class="t"><thead><tr><th>Mã dòng</th><th>Ngày NH</th><th>Nội dung ngân hàng</th><th>Loại</th><th class="num">Ghi Có (tiền vào)</th><th class="num">Ghi Nợ (tiền ra)</th><th class="num">Số dư</th><th>Xử lý</th></tr></thead><tbody>
   <tr><td colspan="6"><i>Số dư đầu kỳ sao kê</i></td><td class="num">${fm(open)}</td><td></td></tr>
   ${rows.map(b=>`<tr><td class="mono small">${esc(b.id)}</td><td>${vd(String(b.vdate).slice(0,10))}</td><td class="small mono">${esc(b.descr)}</td><td class="small">${esc(KIND[b.kind])}${b.ref?' · '+docLink(S.co,{id:b.ref,no:(calc(S.co).by[b.ref]||{}).no||b.ref}):''}</td>
    <td class="num">${b.amt>0?fm(b.amt):''}</td><td class="num">${b.amt<0?fm(-b.amt):''}</td><td class="num">${fm(b.run)}</td>
    <td>${b.st==='matched'?`<span class="chip c-approved">Đã ghi sổ</span> ${b.bs?docLink(S.co,{id:b.bs,no:(calc(S.co).by[b.bs]||{}).no||b.bs}):''}`:canC?
      (b.kind==='unk'?`<select id="bi-${esc(b.id)}" aria-label="Hóa đơn bán"><option value="">Chưa xác định → treo 3388</option>${bis.filter(x=>x.rem>=Math.abs(b.amt)).map(x=>`<option value="${esc(x.d.id)}">${esc(x.d.cust)} · HĐ ${esc(x.d.invNo)} · còn ${fm(x.rem)}</option>`).join('')}</select> `:'')
      +`<button class="btn sm pri" data-act="bankMatch" data-id="${esc(b.id)}">${b.kind==='doc'?'Khớp':'Ghi sổ'}</button>`:'<span class="chip c-pending">Chưa xử lý</span>'}</td></tr>`).join('')}</tbody></table></div>
  ${susp.length?`<div class="panel"><h2>Tiền về chưa rõ đang treo TK 3388</h2><p class="small muted" style="margin:0 0 8px">Khi xác định được khách hàng và hóa đơn (qua điện thoại, ủy nhiệm chi của khách...), phân bổ khoản treo: Nợ 3388 / Có 131. Có thể phân bổ từng phần cho nhiều hóa đơn.</p>
   <div class="tw"><table class="t"><thead><tr><th>Chứng từ</th><th>Nội dung ngân hàng</th><th class="num">Còn treo</th><th>Hóa đơn bán</th><th class="num">Số tiền phân bổ</th><th></th></tr></thead><tbody>${susp.map(x=>`<tr><td>${docLink(S.co,x.d)}</td><td class="small mono">${esc(x.d.descr||'')}</td><td class="num">${fm(x.rem)}</td>
    <td>${canC?`<select id="sb-${esc(x.d.id)}" aria-label="Hóa đơn bán"><option value="">Chọn hóa đơn</option>${bis.map(y=>`<option value="${esc(y.d.id)}" data-rem="${y.rem}">${esc(y.d.cust)} · HĐ ${esc(y.d.invNo)} · còn ${fm(y.rem)}</option>`).join('')}</select>`:''}</td>
    <td>${canC?`<input id="sa-${esc(x.d.id)}" class="num" type="number" min="1" step="1" max="${x.rem}" style="width:130px" aria-label="Số tiền phân bổ">`:''}</td>
    <td>${canC?`<button class="btn sm pri" data-act="suspClear" data-id="${esc(x.d.id)}">Phân bổ</button>`:''}</td></tr>`).join('')}</tbody></table></div></div>`:''}
  <p class="small muted">Bút toán: chi chuyển khoản và nộp tiền mặt ghi qua TK 113 (tiền đang chuyển), khớp sao kê thì Nợ 113 / Có 112 hoặc Nợ 112 / Có 113; thu chuyển khoản đã có giấy báo Có ghi thẳng Nợ 112 / Có 131 và dòng sao kê tự ở trạng thái đã khớp; phí Nợ 6427 (CC700) / Có 112; lãi Nợ 112 / Có 515; tiền về xác định được hóa đơn Nợ 112 / Có 131, chưa xác định Nợ 112 / Có 3388.</p>
  <div class="note warn small"><b>So sánh với cách hạch toán Việt Nam.</b> Lab dùng cách tài khoản trung gian kiểu SAP (bank clearing) để mô phỏng độ trễ ngân hàng: duyệt ủy nhiệm chi ghi <b>Nợ 331 / Có 113</b>; khi sao kê báo Nợ, khớp ở FF67 ghi <b>Nợ 113 / Có 112</b>. Kế toán Việt Nam thường ghi theo thứ tự ngược lại: khi làm thủ tục chuyển tiền <b>Nợ 113 / Có 112</b>, khi nhận giấy báo Nợ <b>Nợ 331 / Có 113</b>. Khác biệt: (1) theo kiểu SAP, nợ phải trả giảm ngay khi duyệt chi, TK 113 có thể dư Có trong thời gian chờ; (2) theo cách Việt Nam, TK 112 giảm ngay, nợ phải trả chỉ giảm khi có chứng từ ngân hàng. Tổng số dư 112 + 113 + 331 cuối cùng như nhau. Muốn ghi thẳng TK 112, tắt ở SPRO.</div></div></div>`;
}

// Hóa đơn bán đã ghi sổ còn phải thu (trừ phiếu thu chờ duyệt/chờ thủ quỹ và phần đã phân bổ qua sao kê)
function biOpen(c){ return c.T.BI.filter(d=>d.status==='posted').map(d=>({d,rem:d.total-c.biPaid(d)-c.biPend(d)})).filter(x=>x.rem>0.5); }
/* ---------- ZBRR: đối chiếu ngân hàng ---------- */
function scrZBRR(){
  const c=calc(S.co); const B=md(S.co).bank; const open=stmtOpen(S.co); const stmt=open+sum(B,b=>+b.amt);
  const book=c.bal('112'); const un=B.filter(b=>b.st==='open'); const unIn=un.filter(b=>b.amt>0), unOut=un.filter(b=>b.amt<0);
  const issued=new Set(B.filter(b=>b.ref).map(b=>b.ref));
  const transit=c.T.PAY.concat(c.T.RC,c.T.CJ).filter(d=>d.status==='posted'&&d.clr==='113'&&!issued.has(d.id));
  const adj=book+sum(unIn,b=>+b.amt)+sum(unOut,b=>+b.amt); const ok=Math.abs(adj-stmt)<1;
  return `<div class="wrap">${head('ZBRR','Bảng đối chiếu tiền gửi ngân hàng','Đối chiếu số dư sổ TK 112 với số dư sao kê đến ngày '+vd(today())+'. Chênh lệch gồm các dòng sao kê chưa được ghi sổ; khoản đang chuyển (TK 113) là phần sổ đã ghi nhưng ngân hàng chưa hạch toán.',`<button class="btn sm pri" data-act="print">In</button>`)}
  <div class="voucher printable"><div class="v-title">BẢNG ĐỐI CHIẾU TIỀN GỬI NGÂN HÀNG</div><div class="v-sub">${esc(coName(S.co))} · Tài khoản tiền gửi tại Ngân hàng TMCP Mô phỏng · Đến ngày ${vd(today())}</div>
  <table class="t"><tbody>
   <tr><td><b>1. Số dư theo sổ kế toán (TK 112)</b></td><td class="num"><b>${fm(book)}</b></td></tr>
   <tr><td>Cộng: tiền vào trên sao kê, sổ chưa ghi</td><td class="num">${fm(sum(unIn,b=>+b.amt))}</td></tr>
   ${unIn.map(b=>`<tr><td class="small" style="padding-left:24px">${vd(String(b.vdate).slice(0,10))} · ${esc(KIND[b.kind])} · ${esc(b.descr)}</td><td class="num small">${fm(b.amt)}</td></tr>`).join('')}
   <tr><td>Trừ: tiền ra trên sao kê, sổ chưa ghi</td><td class="num">${fm(-sum(unOut,b=>+b.amt))}</td></tr>
   ${unOut.map(b=>`<tr><td class="small" style="padding-left:24px">${vd(String(b.vdate).slice(0,10))} · ${esc(KIND[b.kind])} · ${esc(b.descr)}</td><td class="num small">${fm(-b.amt)}</td></tr>`).join('')}
   <tr><td><b>2. Số dư sổ sau điều chỉnh</b></td><td class="num"><b>${fm(adj)}</b></td></tr>
   <tr><td><b>3. Số dư theo sao kê ngân hàng</b></td><td class="num"><b>${fm(stmt)}</b></td></tr>
   <tr><td><b>Chênh lệch (2) − (3)</b></td><td class="num" style="color:${ok?'var(--ok)':'var(--bad)'}"><b>${fm(adj-stmt)}</b></td></tr>
  </tbody></table>
  <div class="note ${ok?'ok':'bad'}" style="margin-top:8px">${ok?`Khớp. Có <b>${un.length}</b> khoản trên sao kê chưa ghi sổ cần xử lý ở FF67.`:'Không khớp – kiểm tra lại sao kê và bút toán TK 112.'}</div>
  <h3 class="sec-title">Khoản đang chuyển (TK 113 = ${fm(c.bal('113'))})</h3>
  ${transit.length?`<table class="t"><tbody>${transit.map(d=>`<tr><td>${docLink(S.co,d)}</td><td>${esc(TYPES[d.type].n)}</td><td>${esc(partnerOf(d))}</td><td>${vd(pdOf(d))}</td><td class="num">${fm(d.type==='PAY'?-d.amount:d.amount)}</td></tr>`).join('')}</tbody></table>`:'<p class="small muted">Không có khoản đang chuyển chưa lên sao kê.</p>'}
  <div class="signs"><div><b>Người lập</b><div class="sg none">(Ký, họ tên)</div></div><div><b>Kế toán trưởng</b><div class="sg none">(Ký, họ tên)</div></div></div></div></div>`;
}

/* ---------- ZTU: tạm ứng ---------- */
function scrZTU(){
  const c=calc(S.co); const me=S.me&&S.me.username; const canC=can('ZTU','C'); const all=S.isAdmin||!canC; const mine=c.T.ADV.filter(d=>d.emp===me||all).slice().reverse();
  const open=mine.find(d=>['pending','approved','paid'].includes(d.status)&&d.emp===me);
  const toSettle=mine.filter(d=>d.status==='paid'&&(d.emp===me||S.isAdmin)&&!c.T.ADS.some(x=>x.adv===d.id&&['pending','approved'].includes(x.status)));
  const sid=S.param&&S.param.adv; const sd=sid&&c.by[sid];
  const bal=calc(S.co).lines.filter(x=>x.j.a==='141'); const owe={}; bal.forEach(x=>{ owe[x.j.p]=(owe[x.j.p]||0)+(x.j.dr||0)-(x.j.cr||0); });
  if(sd&&sd.status==='paid') return `<div class="wrap">${head('ZTU','Thanh toán tạm ứng '+sd.no,'Kê các khoản đã chi kèm số chứng từ gốc. Phần tạm ứng không dùng hết nộp lại quỹ; chi vượt được Thủ quỹ chi bổ sung khi Kế toán trưởng duyệt.')}
   <form class="form panel" data-form="ADS" data-adv="${esc(sd.id)}" data-calc="ADS" data-amt="${sd.amount}"><div class="err"></div>
    <dl class="kv"><dt>Đã tạm ứng</dt><dd class="mono">${fm(sd.amount)}</dd><dt>Lý do</dt><dd>${esc(sd.purpose)}</dd></dl>
    <label class="field" style="max-width:220px"><span>Ngày</span><input id="f-date" type="date" max="${today()}" value="${today()}"></label>
    <div class="tw"><table class="t"><thead><tr><th>TK chi phí</th><th>TTCP</th><th>Nội dung, số chứng từ gốc</th><th class="num">Số tiền</th><th></th></tr></thead><tbody id="ads-lines">${adsRow()}${adsRow()}</tbody></table></div>
    <div><button type="button" class="btn sm" data-act="adsAdd">+ Thêm khoản chi</button></div>
    <div class="form-foot"><span id="f-sum" class="sum"></span><button class="btn pri">Gửi quyết toán</button></div></form></div>`;
  return `<div class="wrap">${head('ZTU','Tạm ứng và thanh toán tạm ứng','Nhân viên đề nghị tạm ứng → Kế toán trưởng duyệt → Thủ quỹ chi và xác nhận (Nợ 141 chi tiết người nhận) → người nhận quyết toán bằng chứng từ chi → Kế toán trưởng duyệt → Thủ quỹ thu lại phần thừa hoặc chi bổ sung. Thủ quỹ không tự chi tạm ứng cho chính mình. Chưa quyết toán khoản cũ thì không tạm ứng tiếp.')}
  ${!canC?'<div class="note">Bạn đang xem các khoản tạm ứng của công ty (vai trò kiểm soát, không lập đề nghị).</div>':open?`<div class="note">Bạn đang có khoản tạm ứng ${docLink(S.co,open)} – ${esc(stLabel(open))}.</div>`:`<form class="form panel" data-form="ADV"><div class="err"></div><h2 style="margin:0">Giấy đề nghị tạm ứng</h2>
   <div class="grid3"><label class="field"><span>Ngày</span><input id="f-date" type="date" max="${today()}" value="${today()}"></label>
   <label class="field"><span>Số tiền *</span><input id="f-amt" class="num" type="number" min="1" step="1" required></label>
   <label class="field" style="grid-column:1/-1"><span>Lý do tạm ứng *</span><input id="f-purpose" maxlength="200" required placeholder="Công tác phí, mua vật tư lẻ…"></label></div>
   <div class="form-foot"><span></span><button class="btn pri">Gửi đề nghị</button></div></form>`}
  ${toSettle.length?`<div class="panel"><h2>Chờ thanh toán tạm ứng</h2><div class="tw"><table class="t"><tbody>${toSettle.map(d=>`<tr><td>${docLink(S.co,d)}</td><td>${esc(d.empName)}</td><td class="num">${fm(d.amount)}</td><td><button class="btn sm pri" data-go="ZTU" data-p="${P({adv:d.id})}">Lập giấy thanh toán</button></td></tr>`).join('')}</tbody></table></div></div>`:''}
  <div><h3 class="sec-title">Các khoản tạm ứng ${all?'của công ty':'của bạn'}</h3><div class="tw"><table class="t"><thead><tr><th>Số</th><th>Người tạm ứng</th><th>Lý do</th><th class="num">Số tiền</th><th>Trạng thái</th></tr></thead><tbody>
  ${mine.map(d=>`<tr class="click" data-go="DOC" data-p="${P({co:S.co,id:d.id})}"><td class="mono">${esc(d.no)}</td><td>${esc(d.empName)}</td><td class="small">${esc(d.purpose)}</td><td class="num">${fm(d.amount)}</td><td>${chip(d)}</td></tr>`).join('')||'<tr><td colspan="5" class="muted">Chưa có.</td></tr>'}</tbody></table></div></div>
  ${Object.keys(owe).some(k=>owe[k])?`<div><h3 class="sec-title">Số dư TK 141 theo người nhận tạm ứng</h3><div class="tw"><table class="t"><tbody>${Object.keys(owe).filter(k=>owe[k]).map(k=>`<tr><td class="mono">${esc(k)}</td><td class="num">${fm(owe[k])}</td></tr>`).join('')}</tbody></table></div></div>`:''}</div>`;
}
function adsRow(){ const accs=manualAccs().filter(a=>/^(6|811|1331|242)/.test(a));
  return `<tr><td><select class="ads-a" data-chg="adsacc">${accOpts('',accs)}</select></td><td><select class="ads-cc" disabled>${ccOpts('')}</select></td>
  <td><input class="ads-memo" maxlength="120" placeholder="Vé xe HĐ 0012345"></td><td><input class="ads-amt num" type="number" min="1" step="1"></td><td><button type="button" class="btn sm" data-act="glDel">✕</button></td></tr>`; }

/* ---------- SPRO (giảng viên): ngày làm việc, kiểm quỹ, sao kê ---------- */
globalThis.sproGL = function(){
  const A=S.adm||{}; const cf=S.cfg;
  return `<div class="panel"><h2>Ngày làm việc và kỳ (P3)</h2>
   <p class="small muted" style="margin-top:0">Mọi chứng từ ghi sổ theo ngày làm việc của công ty. Tua ngày tới để mô phỏng thời gian trôi; khi tua, ngân hàng phát hành sao kê đến ngày mới.</p>
   <div class="tw"><table class="t"><thead><tr><th>Công ty</th><th>Ngày làm việc</th><th class="num">Số kiểm đếm quỹ (ẩn với SV)</th><th>Khoản sao kê cài sẵn</th></tr></thead><tbody>
   ${COS.map(co=>{const a=A[co]||{};const pr=a.presets||[];return `<tr><td class="mono">${co}</td><td>${vd(a.wdate||'')}</td><td class="num">${a.cash!=null?fm(a.cash):'<span class="muted">chưa nhập</span>'}</td>
     <td class="small">${pr.map(p=>`${vd(String(p.vdate).slice(0,10))} ${esc(KIND[p.kind])} ${fm(p.amt)}${p.issued?' ✓':''}`).join('<br>')}</td></tr>`;}).join('')}</tbody></table></div>
   <form class="form" data-form="STATE" style="margin-top:10px"><div class="err"></div>
    <div class="grid3"><label class="field"><span>Áp cho</span><select id="s-co"><option value="">Cả 8 công ty</option>${COS.map(c=>`<option ${c===S.co?'selected':''}>${c}</option>`).join('')}</select></label>
    <label class="field"><span>Ngày làm việc mới</span><input id="s-wdate" type="date" value="${esc((A[S.co]||{}).wdate||realToday())}"></label>
    <label class="field"><span>Số tiền mặt kiểm đếm thực tế (để trống = chưa cho kiểm quỹ)</span><input id="s-cash" class="num" type="number" min="0" step="1000" value="${(A[S.co]||{}).cash??''}"></label>
    <label class="field"><span>Cài lại 3 khoản sao kê cho tháng của ngày làm việc</span><select id="s-reseed"><option value="0">Không</option><option value="1">Có</option></select></label>
    <label class="field"><span>Chi/thu chuyển khoản qua TK 113 (tiền đang chuyển)</span><select id="s-clear"><option value="1" ${cf.bankClear!==false?'selected':''}>Bật – cần khớp sao kê (FF67)</option><option value="0" ${cf.bankClear===false?'selected':''}>Tắt – ghi thẳng TK 112 như bản P1</option></select></label></div>
    <div class="form-foot"><span class="small muted">Không đặt được ngày trước ngày mở sổ. Lùi ngày làm việc chỉ nên dùng khi làm lại bài.</span><button class="btn pri">Lưu</button></div></form></div>`;
};

/* ---------- Biểu mẫu ---------- */
const FORMS = {
  GLJE(f){ const {lines,bad}=readJE(f); const memo=val(f,'f-memo');
    if(bad) return setErr(f,'<b>'+esc(bad)+'</b>');
    if(lines.length<2) return setErr(f,'<b>Bút toán phải có ít nhất hai dòng.</b>');
    const dr=sum(lines,l=>l.dr||0), cr=sum(lines,l=>l.cr||0); if(dr!==cr) return setErr(f,'<b>Bút toán không cân:</b> Nợ '+fm(dr)+' ≠ Có '+fm(cr)+'.');
    if(!memo) return setErr(f,'<b>Thiếu diễn giải.</b>');
    guard(f,async()=>{ const r=await createDoc(S.co,'JE',{kind:f.dataset.kind,date:val(f,'f-date'),memo,lines});
      toast('Đã lưu bút toán '+r.no+', chờ Kế toán trưởng duyệt.'); go('DOC',{co:S.co,id:r.id}); }); },
  GLREV(f){ const reason=val(f,'f-reason'); if(!reason) return setErr(f,'<b>Thiếu lý do đảo.</b>');
    guard(f,async()=>{ const r=await createDoc(S.co,'JE',{kind:'rev',revOf:f.dataset.id,reason,date:today()}); toast('Đã lập bút toán đảo '+r.no+', chờ duyệt.'); go('DOC',{co:S.co,id:r.id}); }); },
  FB03(f){ go('FB03',{q:val(f,'f-q'),t:val(f,'f-t')}); },
  FAGL(f){ go('FAGLL03',{acc:val(f,'f-acc'),from:val(f,'f-from'),to:val(f,'f-to'),partner:f.querySelector('#f-par')?val(f,'f-par'):'',cc:f.querySelector('#f-cc')?val(f,'f-cc'):''}); },
  TBP(f){ go('F.01',{from:val(f,'f-from'),to:val(f,'f-to')}); },
  ZSO(f){ go('ZSO',{k:val(f,'f-k'),acc:val(f,'f-acc'),from:val(f,'f-from'),to:val(f,'f-to')}); },
  CJ(f){ const dir=val(f,'f-dir'), bank=['wd','dep'].includes(dir); const amt=Math.round(num(val(f,'f-amt'))), acc=bank?'':val(f,'f-acc'), cc=bank?'':val(f,'f-cc');
    if(!(amt>0)) return setErr(f,'<b>Số tiền phải lớn hơn 0.</b>'); if(!bank&&!acc) return setErr(f,'<b>Chọn tài khoản đối ứng.</b>');
    if(acc&&ccNeed(acc)&&!cc) return setErr(f,'<b>TK '+esc(acc)+' bắt buộc chọn trung tâm chi phí.</b>');
    if(['out','dep'].includes(dir)&&amt>cashBook(S.co).close) return setErr(f,'<b>Vượt tồn quỹ</b> ('+fm(cashBook(S.co).close)+' đồng). Tồn quỹ không được âm.');
    guard(f,async()=>{ const b={dir,date:val(f,'f-date'),amount:amt,person:val(f,'f-person'),reason:val(f,'f-reason')}; if(acc){ b.acc=acc; if(cc) b.cc=cc; }
      const r=await createDoc(S.co,'CJ',b); toast('Đã lưu '+CJDIR[dir].toLowerCase()+' '+r.no+', chờ Kế toán trưởng duyệt.'); render(true,true); }); },
  CNT(f){ guard(f,async()=>{ const r=await createDoc(S.co,'CNT',{date:val(f,'f-date'),members:val(f,'f-members'),reason:val(f,'f-reason')});
      toast(r.status==='posted'?'Biên bản '+r.no+': tiền thực tế khớp sổ.':'Biên bản '+r.no+' có chênh lệch, chờ Kế toán trưởng duyệt.'); go('DOC',{co:S.co,id:r.id}); }); },
  ADV(f){ const amt=Math.round(num(val(f,'f-amt'))); if(!(amt>0)) return setErr(f,'<b>Số tiền phải lớn hơn 0.</b>');
    guard(f,async()=>{ const r=await createDoc(S.co,'ADV',{date:val(f,'f-date'),amount:amt,purpose:val(f,'f-purpose')}); toast('Đã gửi đề nghị tạm ứng '+r.no+'.'); render(true,true); }); },
  ADS(f){ const lines=[]; let bad='';
    f.querySelectorAll('#ads-lines tr').forEach(tr=>{ const a=tr.querySelector('.ads-a').value, cc=tr.querySelector('.ads-cc').value, memo=tr.querySelector('.ads-memo').value.trim(), amount=Math.round(num(tr.querySelector('.ads-amt').value));
      if(!a&&!amount) return; if(!a||!(amount>0)||!memo){ bad=bad||'Mỗi khoản chi cần tài khoản, nội dung và số tiền.'; return; }
      if(ccNeed(a)&&!cc){ bad=bad||'TK '+a+' bắt buộc chọn trung tâm chi phí.'; return; } lines.push(Object.assign({a,amount,memo},cc?{cc}:{})); });
    if(bad) return setErr(f,'<b>'+esc(bad)+'</b>'); if(!lines.length) return setErr(f,'<b>Chưa có khoản chi nào.</b>');
    guard(f,async()=>{ const r=await createDoc(S.co,'ADS',{adv:f.dataset.adv,date:val(f,'f-date'),lines}); toast('Đã gửi giấy thanh toán tạm ứng '+r.no+'.'); go('DOC',{co:S.co,id:r.id}); }); },
  STATE(f){ const co=val(f,'s-co'); const st={wdate:val(f,'s-wdate'),cashCount:val(f,'s-cash'),reseed:val(f,'s-reseed')==='1'};
    guard(f,async()=>{
      const cf=Object.assign({},S.cfg,{bankClear:val(f,'s-clear')==='1'});
      if(cf.bankClear!==(S.cfg.bankClear!==false)) await api('erp_admin_set_cfg',{p_token:S.token,p_cfg:cf});
      const r=await api('erp_admin_set_state',{p_token:S.token,p_co:co,p_state:st}); await sync();
      const n=Object.values(r||{}).reduce((s,x)=>s+(+x||0),0); toast('Đã lưu. Ngân hàng phát hành '+n+' dòng sao kê mới.'); render(true,true); }); }
};
const ACTS = {
  glAdd(){ const tb=document.getElementById('gl-lines'); if(tb.children.length>=12) return toast('Tối đa 12 dòng.'); tb.insertAdjacentHTML('beforeend',jeRow()); },
  adsAdd(){ const tb=document.getElementById('ads-lines'); if(tb.children.length>=10) return toast('Tối đa 10 khoản.'); tb.insertAdjacentHTML('beforeend',adsRow()); },
  glDel(a){ const tr=a.closest('tr'); const tb=tr.parentNode; if(tb.children.length<=1) return; tr.remove(); const f=tb.closest('form'); if(f&&CALC[f.dataset.calc]) CALC[f.dataset.calc](f); },
  print(){ window.print(); },
  glCsv(){ const p=Object.assign({acc:'112'},S.param||{}); const r=glQuery(S.co,p);
    csvDownload('FAGLL03_'+S.co+'_'+p.acc+'_'+r.from+'_'+r.to+'.csv',[['Ngày ghi sổ','Số chứng từ','Số bút toán','Diễn giải','Đối tượng','TTCP','Nợ','Có','Số dư']]
      .concat([['','','','Số dư đầu kỳ','','','','',r.open]]).concat(r.rows.map(x=>[x.pd,x.d.no,x.d.jeNo||'',x.j.memo||x.d.memo||TYPES[x.d.type].n,x.j.p||x.j.mat||'',x.j.cc||'',x.j.dr||0,x.j.cr||0,x.run]))); },
  tbCsv(){ const tbl=document.querySelector('.wrap table.t'); if(!tbl) return; const rows=[...tbl.querySelectorAll('tr')].map(tr=>[...tr.children].map(td=>td.textContent.trim().replace(/\./g,'')));
    csvDownload('F01_'+S.co+'.csv',rows); },
  async period(a){ const close=a.dataset.close==='1'; a.disabled=true;
    try{ await api('erp_period_set',{p_token:S.token,p_co:S.co,p_fy:+a.dataset.fy,p_period:+a.dataset.per,p_grp:a.dataset.grp,p_close:close,p_act_role:actRole()}); await sync();
      toast((close?'Đã đóng ':'Đã mở ')+'kỳ '+String(a.dataset.per).padStart(2,'0')+'/'+a.dataset.fy+' – '+GRP[a.dataset.grp]+'.'); render(true,true); }catch(e){ toast(dbErr(e)); a.disabled=false; } },
  async cashOk(a){ const d=calc(S.co).by[a.dataset.id]; if(!d) return; const [k,amt]=cashDir(d);
    a.disabled=true;
    try{ await api('erp_cash_confirm',{p_token:S.token,p_co:S.co,p_id:d.id,p_act_role:actRole()}); await sync(); toast('Đã ghi sổ quỹ theo '+d.no+'.'); render(true,true); }catch(e){ toast(dbErr(e)); a.disabled=false; } },
  async cashBack(a){ const id=a.dataset.id; const note=(document.getElementById('rt-'+id).value||'').trim();
    if(!note) return toast('Ghi lý do trả lại (ví dụ người nhận không đến, sai số tiền).'); a.disabled=true;
    try{ await api('erp_cash_return',{p_token:S.token,p_co:S.co,p_id:id,p_note:note,p_act_role:actRole()}); await sync(); toast('Đã trả lại chứng từ, không ghi sổ.'); render(true,true); }catch(e){ toast(dbErr(e)); a.disabled=false; } },
  async suspClear(a){ const id=a.dataset.id; const bi=document.getElementById('sb-'+id).value; const amt=Math.round(num(document.getElementById('sa-'+id).value));
    if(!bi) return toast('Chọn hóa đơn bán cần phân bổ.'); if(!(amt>0)) return toast('Nhập số tiền phân bổ.'); a.disabled=true;
    try{ const r=await api('erp_susp_clear',{p_token:S.token,p_co:S.co,p_bs:id,p_bi:bi,p_amount:amt,p_act_role:actRole()}); await sync(); toast('Đã phân bổ, chứng từ '+r.no+'.'); render(true,true); }catch(e){ toast(dbErr(e)); a.disabled=false; } },
  async bankRefresh(a){ a.disabled=true;
    try{ const n=await api('erp_bank_refresh',{p_token:S.token,p_co:S.co}); await sync(); toast(n?'Nhận '+n+' dòng sao kê mới.':'Không có dòng sao kê mới.'); render(true,true); }catch(e){ toast(dbErr(e)); a.disabled=false; } },
  async bankMatch(a){ const id=a.dataset.id; const s=document.getElementById('bi-'+id); a.disabled=true;
    try{ const r=await api('erp_bank_match',{p_token:S.token,p_co:S.co,p_line:id,p_opts:s&&s.value?{bi:s.value}:{},p_act_role:actRole()}); await sync(); toast('Đã ghi sổ dòng sao kê '+id+' (chứng từ '+r.no+').'); render(true,true); }catch(e){ toast(dbErr(e)); a.disabled=false; } }
};
const CHGS = {
  glacc(s){ const tr=s.closest('tr'); const cc=tr.querySelector('.gl-cc'); cc.disabled=!ccNeed(s.value); if(cc.disabled) cc.value=''; },
  cjdir(s){ const f=s.closest('form'); const bank=['wd','dep'].includes(s.value);
    f.querySelectorAll('.cj-acc').forEach(x=>x.hidden=bank); f.querySelector('.cj-bank').hidden=!bank; if(CALC.CJ) CALC.CJ(f); },
  cjacc(s){ const cc=document.getElementById('f-cc'); cc.disabled=!ccNeed(s.value); if(cc.disabled) cc.value=''; },
  adsacc(s){ const cc=s.closest('tr').querySelector('.ads-cc'); cc.disabled=!ccNeed(s.value); if(cc.disabled) cc.value=''; }
};
const CALCS = {
  GLJE(f){ let dr=0,cr=0; f.querySelectorAll('#gl-lines tr').forEach(tr=>{ dr+=num(tr.querySelector('.gl-dr').value); cr+=num(tr.querySelector('.gl-cr').value); });
    const d=dr-cr; f.querySelector('#f-sum').innerHTML=`<span>Tổng Nợ <b>${fm(dr)}</b></span><span>Tổng Có <b>${fm(cr)}</b></span><span>Chênh lệch <b style="color:${d?'var(--bad)':'var(--ok)'}">${fm(d)}</b></span>`; },
  CJ(f){ const amt=num(val(f,'f-amt')); const t=cashBook(S.co).close; const out=['out','dep'].includes(val(f,'f-dir'));
    f.querySelector('#f-sum').innerHTML=`<span>Tồn quỹ <b>${fm(t)}</b></span><span>Sau phiếu <b style="color:${out&&amt>t?'var(--bad)':'inherit'}">${fm(out?t-amt:t+amt)}</b></span>`; },
  ADS(f){ let e=0; f.querySelectorAll('#ads-lines .ads-amt').forEach(i=>e+=num(i.value)); const adv=num(f.dataset.amt); const r=adv-e;
    f.querySelector('#f-sum').innerHTML=`<span>Đã chi <b>${fm(e)}</b></span><span>${r>=0?'Nộp lại quỹ':'Chi bổ sung'} <b>${fm(Math.abs(r))}</b></span>`; }
};

const FI='Kế toán (FI)', CASH='Tiền & ngân hàng';
const OPS=['KHO','MH','KD','KT','AP','AR','TH','TQ','GD','SX','NS','GT','TS'];
erpModule({name:'P3 sổ cái, tiền, ngân hàng',
  tc:{
    'FB50':{m:FI,t:'Lập bút toán tổng hợp',r:['TH']},
    'FBS1':{m:FI,t:'Bút toán trích trước (tự đảo)',r:['TH']},
    'FB08':{m:FI,t:'Đảo bút toán',r:['TH']},
    'FB03':{m:FI,t:'Hiển thị chứng từ kế toán',r:ALL},
    'FAGLL03':{m:FI,t:'Sổ cái theo tài khoản',r:['TH','TQ','KTT','AP','AR','GD','KSNB']},
    'ZSO':{m:FI,t:'Sổ kế toán theo mẫu (in)',r:['TH','TQ','KTT','GD','KSNB']},
    'OB52':{m:FI,t:'Đóng / mở kỳ kế toán',r:ALL},
    'FBCJ':{m:CASH,t:'Quỹ tiền mặt – phiếu thu, chi',r:['TH','AP','AR','KT','TQ','KTT','GD','KSNB']},
    'ZKQ':{m:CASH,t:'Kiểm kê quỹ',r:['TQ','KTT','KSNB']},
    'FF67':{m:CASH,t:'Sao kê ngân hàng',r:['TH','KTT','GD','KSNB']},
    'ZBRR':{m:CASH,t:'Đối chiếu tiền gửi ngân hàng',r:['TH','KTT','GD','KSNB']},
    'ZTU':{m:CASH,t:'Tạm ứng và thanh toán tạm ứng',r:OPS}
  },
  screens:{FB50:()=>scrJE('man'),FBS1:()=>scrJE('acc'),FB08:scrFB08,FB03:scrFB03,FAGLL03:scrFAGLL03,ZSO:scrZSO,OB52:scrOB52,
           FBCJ:scrFBCJ,ZKQ:scrZKQ,FF67:scrFF67,ZBRR:scrZBRR,ZTU:scrZTU},
  forms:FORMS, acts:ACTS, chg:CHGS, calc:CALCS
});
Object.assign(LIVE_FORM,{FB50:1,FBS1:1,FB08:1,FBCJ:1,ZKQ:1,ZTU:1});
globalThis.scrTBp = scrTBp;
})();
