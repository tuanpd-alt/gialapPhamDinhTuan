"use strict";
/* ERP Lab – P2: Dữ liệu gốc (vật tư, nhà cung cấp, khách hàng, bảng giá), hệ thống tài khoản, cơ cấu tổ chức,
   duyệt thay đổi dữ liệu gốc nhạy cảm (ZMDA) và nhật ký thay đổi (ZCHG). Máy chủ kiểm tra quyền và ghi nhật ký. */
(function(){
/* ---------- Định nghĩa đối tượng ---------- */
// f: tên trường máy chủ (erp_md_save), k: khóa trong dữ liệu đồng bộ, s: trường nhạy cảm (phải chờ Kế toán trưởng duyệt).
const OBJ = {
  MAT:{n:'vật tư',N:'Vật tư',tc:['MM01','MM02','MM03'],list:co=>matsOf(co),
    fields:[{f:'mtype',k:'t',l:'Loại vật tư',type:'mtype',createOnly:1},{f:'name',k:'n',l:'Tên vật tư',req:1,max:120},{f:'unit',k:'u',l:'Đơn vị tính',req:1,max:20},
      {f:'buy_price',k:'bp',l:'Giá mua tham khảo (chưa VAT)',type:'num'},{f:'sell_price',k:'sp',l:'Giá bán niêm yết (chưa VAT)',type:'num'},
      {f:'min_stock',k:'min',l:'Tồn kho tối thiểu',type:'num'},{f:'valid_from',k:'from',l:'Có hiệu lực từ ngày',type:'date'},{f:'active',k:'active',l:'Trạng thái',type:'active',s:1}]},
  VEN:{n:'nhà cung cấp',N:'Nhà cung cấp',tc:['XK01','XK02','XK03'],list:co=>vensOf(co),
    fields:[{f:'name',k:'n',l:'Tên nhà cung cấp',req:1,max:160},{f:'mst',k:'mst',l:'Mã số thuế',req:1,max:14,ph:'10 chữ số, chi nhánh dạng 0123456789-001'},{f:'address',k:'addr',l:'Địa chỉ',max:200},
      {f:'terms',k:'terms',l:'Thời hạn thanh toán (ngày)',type:'num',s:1},{f:'bank_acc',k:'bank',l:'Số tài khoản ngân hàng nhận tiền',max:30,s:1},{f:'bank_name',k:'bankName',l:'Ngân hàng, chi nhánh',max:120,s:1},
      {f:'active',k:'active',l:'Trạng thái',type:'active',s:1}]},
  CUS:{n:'khách hàng',N:'Khách hàng',tc:['XD01','XD02','XD03'],list:co=>custsOf(co),
    fields:[{f:'name',k:'n',l:'Tên khách hàng',req:1,max:160},{f:'mst',k:'mst',l:'Mã số thuế',req:1,max:14,ph:'10 chữ số, chi nhánh dạng 0123456789-001'},{f:'address',k:'addr',l:'Địa chỉ',max:200},
      {f:'terms',k:'terms',l:'Thời hạn thanh toán (ngày)',type:'num',s:1},{f:'credit_lim',k:'lim',l:'Hạn mức tín dụng (đồng)',type:'num',s:1},
      {f:'bank_acc',k:'bank',l:'Số tài khoản ngân hàng của khách',max:30,s:1},{f:'bank_name',k:'bankName',l:'Ngân hàng, chi nhánh',max:120,s:1},
      {f:'active',k:'active',l:'Trạng thái',type:'active',s:1}]}
};
const OBJ_OF_TC = {}; Object.keys(OBJ).forEach(o=>OBJ[o].tc.forEach((t,i)=>OBJ_OF_TC[t]={o,mode:['create','change','show'][i]}));
const FIELD_NAME = {}; Object.keys(OBJ).forEach(o=>OBJ[o].fields.forEach(x=>FIELD_NAME[o+'.'+x.f]=x.l));
FIELD_NAME['PRICE.price']='Đơn giá mua';
const fieldName = (obj,f) => f==='*tạo mới'?'Tạo mới':(FIELD_NAME[obj+'.'+f]||(String(f).startsWith('price')?'Đơn giá mua '+String(f).slice(5).trim():f));
const OBJ_NAME = {MAT:'Vật tư',VEN:'Nhà cung cấp',CUS:'Khách hàng',PRICE:'Bảng giá mua'};
const md = co => mdOf(co) || {mats:[],partners:[],prices:[],chg:[],org:[]};
const pendOf = (co,obj,key) => md(co).chg.filter(c=>c.obj===obj&&c.key===key&&c.st==='pending');
const recOf = (co,obj,key) => OBJ[obj].list(co).find(x=>x.c===key);
const actRole = () => S.isAdmin?S.role:'';
const showVal = (obj,f,v) => {
  if(v==null||v==='') return '<span class="muted">—</span>';
  if(f==='active') return String(v)==='true'?'Đang dùng':'Khóa';
  if(f==='mtype') return esc(MTYPE[v]||v);
  if(['buy_price','sell_price','credit_lim','price','min_stock'].includes(f)||String(f).startsWith('price')) return fm(v);
  if(f==='valid_from') return vd(String(v).slice(0,10));
  return esc(v);
};
function statusChip(x){
  if(x.ok===false) return '<span class="chip c-pending">Chờ xác nhận</span>';
  if(x.active===false) return '<span class="chip c-rejected">Khóa</span>';
  if(x.from&&String(x.from).slice(0,10)>today()) return '<span class="chip c-info">Chưa hiệu lực</span>';
  return '<span class="chip c-approved">Đang dùng</span>';
}

/* ---------- Danh sách (MM03, XK03, XD03; MM02/XK02/XD02 khi chưa chọn đối tượng) ---------- */
function mdList(obj,mode){
  const O=OBJ[obj], tc=O.tc[mode==='change'?1:2], rows=O.list(S.co);
  const canC = can(O.tc[0],'C');
  const cols = obj==='MAT'
    ? [['Mã',x=>`<span class="mono">${esc(x.c)}</span>`],['Tên',x=>esc(x.n)],['Loại · TK',x=>esc(x.t)+(x.acc?' · '+esc(x.acc):'')],['ĐVT',x=>esc(x.u)],['Giá mua TK',x=>fm(x.bp),1],['Giá bán',x=>fm(x.sp),1],['Tồn tối thiểu',x=>x.min||'',1]]
    : [['Mã',x=>`<span class="mono">${esc(x.c)}</span>`],['Tên',x=>esc(x.n)],['Mã số thuế',x=>`<span class="mono">${esc(x.mst)}</span>`],['Hạn TT',x=>x.terms+' ngày',1]]
      .concat(obj==='CUS'?[['Hạn mức',x=>fm(x.lim),1]]:[['Tài khoản nhận tiền',x=>x.bank?`<span class="mono">${esc(x.bank)}</span>`:'<span class="muted">chưa có</span>']]);
  const go2 = mode==='change'&&canC ? O.tc[1] : O.tc[2];
  return `<div class="wrap">${head(tc,(mode==='change'?'Thay đổi ':'Danh mục ')+O.n,
      mode==='change'?'Chọn một '+O.n+' để thay đổi. Trường có dấu ◆ là trường nhạy cảm: thay đổi chỉ có hiệu lực sau khi Kế toán trưởng duyệt (ZMDA).'
      :'Dữ liệu gốc dùng chung cho mọi chứng từ của công ty. Bấm vào một dòng để xem chi tiết và lịch sử thay đổi.',
      canC?`<button class="btn sm pri" data-go="${O.tc[0]}">+ Tạo ${esc(O.n)}</button>`:'')}
  <div class="tw"><table class="t"><thead><tr>${cols.map(c=>`<th class="${c[2]?'num':''}">${c[0]}</th>`).join('')}<th>Trạng thái</th><th class="num">Chờ duyệt</th></tr></thead><tbody>
  ${rows.map(x=>{const p=pendOf(S.co,obj,x.c).length;return `<tr class="click" data-go="${go2}" data-p="${P({key:x.c})}">${cols.map(c=>`<td class="${c[2]?'num':''}">${c[1](x)}</td>`).join('')}<td>${statusChip(x)}</td><td class="num">${p?`<span class="chip c-pending">${p}</span>`:''}</td></tr>`;}).join('')
    ||`<tr><td colspan="${cols.length+2}" class="muted">Chưa có ${esc(O.n)} nào.</td></tr>`}</tbody></table></div></div>`;
}

/* ---------- Biểu mẫu tạo / thay đổi ---------- */
function inputFor(obj,x,rec,mode){
  const v = rec?rec[x.k]:(x.f==='active'?true:x.f==='valid_from'?today():x.f==='terms'?30:'');
  const id='md-'+x.f, lab=`<span>${esc(x.l)}${x.s&&mode==='change'?' <b title="Trường nhạy cảm – cần Kế toán trưởng duyệt" style="color:var(--warn)">◆</b>':''}${x.req?' *':''}</span>`;
  if(x.type==='mtype'){
    if(mode!=='create') return `<label class="field">${lab}<input value="${esc(MTYPE[v]||v)}" disabled></label>`;
    return `<label class="field">${lab}<select id="${id}">${Object.keys(MTYPE).map(k=>`<option value="${k}">${k} · ${esc(MTYPE[k])}</option>`).join('')}</select></label>`;
  }
  if(x.type==='active'){
    if(mode==='create') return '';
    return `<label class="field">${lab}<select id="${id}"><option value="true" ${String(v)!=='false'?'selected':''}>Đang dùng</option><option value="false" ${String(v)==='false'?'selected':''}>Khóa (không cho dùng trên chứng từ mới)</option></select></label>`;
  }
  if(x.type==='num') return `<label class="field">${lab}<input id="${id}" class="num" type="number" min="0" step="1" value="${esc(v===''?'':v)}"></label>`;
  if(x.type==='date') return `<label class="field">${lab}<input id="${id}" type="date" value="${esc(String(v||'').slice(0,10))}"></label>`;
  return `<label class="field">${lab}<input id="${id}" ${x.max?`maxlength="${x.max}"`:''} ${x.req?'required':''} placeholder="${esc(x.ph||'')}" value="${esc(v??'')}"></label>`;
}
function mdForm(obj,mode){
  const O=OBJ[obj], tc=O.tc[mode==='create'?0:1];
  const key=S.param&&S.param.key; const rec=mode==='change'?recOf(S.co,obj,key):null;
  if(mode==='change'&&!key) return mdList(obj,'change');
  if(mode==='change'&&!rec) return `<div class="wrap">${head(tc,'Thay đổi '+O.n,'')}<div class="err">Không tìm thấy ${esc(O.n)} ${esc(key)}.</div></div>`;
  const pend = rec?pendOf(S.co,obj,key):[];
  const fields = O.fields.filter(x=>!(mode==='create'&&x.type==='active'));
  const intro = mode==='create'
    ? (obj==='MAT'?'Mã vật tư do hệ thống cấp theo loại (HHnn, NVnn, TPnn, DVnn). Tài khoản tồn kho xác định tự động: NVL → 152, TP → 155, HH → 156; dịch vụ không theo dõi tồn kho. Hệ thống chặn tạo trùng tên.'
       :'Mã đối tượng do hệ thống cấp. Hệ thống chặn trùng mã số thuế. Đối tượng mới ở trạng thái <b>chờ xác nhận</b>: chưa dùng được trên chứng từ cho đến khi Kế toán trưởng duyệt (ZMDA).')
    : 'Trường thường có hiệu lực ngay. Trường có dấu ◆ chỉ có hiệu lực sau khi Kế toán trưởng duyệt; trong lúc chờ, chứng từ vẫn dùng giá trị cũ.';
  return `<div class="wrap">${head(tc,(mode==='create'?'Tạo ':'Thay đổi ')+O.n+(rec?' '+rec.c:''),intro,rec?`<button class="btn sm" data-go="${O.tc[2]}" data-p="${P({key})}">Xem lịch sử</button>`:'')}
  ${pend.length?`<div class="note warn"><b>${pend.length} thay đổi đang chờ Kế toán trưởng duyệt:</b> ${pend.map(c=>`${esc(fieldName(obj,c.f))}: ${showVal(obj,c.f,c.o)} → ${showVal(obj,c.f,c.n)}`).join('; ')}</div>`:''}
  <form class="form panel" data-form="MDSAVE" data-obj="${obj}" data-key="${esc(key||'')}"><div class="err"></div>
   <div class="grid3">${fields.map(x=>inputFor(obj,x,rec,mode)).join('')}</div>
   <div class="form-foot"><span class="small muted">${mode==='create'?'Mọi lần tạo, sửa đều ghi vào nhật ký thay đổi (ZCHG) với người thực hiện và thời điểm.':'Chỉ các trường có giá trị khác hiện tại mới được gửi đi.'}</span><button class="btn pri">${mode==='create'?'Tạo '+esc(O.n):'Lưu thay đổi'}</button></div></form></div>`;
}

/* ---------- Hiển thị chi tiết (MM03/XK03/XD03 có key) ---------- */
function mdShow(obj){
  const O=OBJ[obj], key=S.param&&S.param.key;
  if(!key) return mdList(obj,'show');
  const rec=recOf(S.co,obj,key); if(!rec) return `<div class="wrap">${head(O.tc[2],O.N,'')}<div class="err">Không tìm thấy ${esc(key)}.</div></div>`;
  const hist = md(S.co).chg.filter(c=>c.obj===obj&&c.key===key || (obj!=='CUS'&&c.obj==='PRICE'&&(obj==='VEN'?c.key.startsWith(key+'/'):c.key.endsWith('/'+key))));
  const canC = can(O.tc[0],'C');
  let extra='';
  if(obj==='MAT'&&isStock(rec)){ const s=calc(S.co).st[key]||{q:0,v:0,avg:0}; extra=`<dt>Tồn hiện tại</dt><dd>${s.q} ${esc(rec.u)} · ${fm(s.v)} đồng (BQ ${fm(s.avg)})</dd><dt>Kho lưu trữ</dt><dd>${esc(rec.sloc||'—')}</dd><dt>Nhóm lợi nhuận</dt><dd>${esc(rec.pc||'—')}</dd>`; }
  if(obj!=='MAT'){ const c=calc(S.co); const b=obj==='VEN'?c.ap[key]:c.ar[key]; if(b) extra=`<dt>Số dư ${obj==='VEN'?'phải trả (331)':'phải thu (131)'}</dt><dd class="mono">${fm(obj==='VEN'?b.cr-b.dr:b.dr-b.cr)}</dd>`; }
  if(obj==='VEN'){ const pr=md(S.co).prices.filter(p=>p.v===key); if(pr.length) extra+=`<dt>Bảng giá ME11</dt><dd>${pr.map(p=>`${esc(p.m)}: ${fm(p.p)} (từ ${vd(String(p.from).slice(0,10))})`).join('; ')}</dd>`; }
  return `<div class="wrap">${head(O.tc[2],O.N+' '+rec.c+' · '+rec.n,'',canC?`<button class="btn sm pri" data-go="${O.tc[1]}" data-p="${P({key})}">Thay đổi</button>`:'')}
  <div class="panel"><dl class="kv"><dt>Trạng thái</dt><dd>${statusChip(rec)}</dd>${O.fields.filter(x=>x.f!=='active').map(x=>`<dt>${esc(x.l)}</dt><dd>${showVal(obj,x.f,rec[x.k])}</dd>`).join('')}${obj==='MAT'?`<dt>Tài khoản tồn kho</dt><dd>${rec.acc?esc(rec.acc)+' · '+esc(ACCS[rec.acc]||''):'Không theo dõi tồn kho'}</dd>`:''}${extra}</dl></div>
  <div class="panel"><h2>Lịch sử thay đổi</h2>${chgTable(hist,true)}</div></div>`;
}
function chgTable(rows,short){
  if(!rows.length) return '<p class="muted small" style="margin:0">Chưa có thay đổi nào được ghi nhận.</p>';
  const ST={applied:['c-approved','Đã áp dụng'],pending:['c-pending','Chờ duyệt'],approved:['c-approved','Đã duyệt'],rejected:['c-rejected','Từ chối']};
  return `<div class="tw"><table class="t"><thead><tr><th>Thời điểm</th>${short?'':'<th>Đối tượng</th>'}<th>Trường</th><th>Giá trị cũ</th><th>Giá trị mới</th><th>Người yêu cầu</th><th>Trạng thái</th><th>Người duyệt</th></tr></thead><tbody>
  ${rows.map(c=>`<tr><td class="small">${vdt(c.at)}</td>${short?'':`<td>${esc(OBJ_NAME[c.obj]||c.obj)} <span class="mono">${esc(c.key)}</span></td>`}<td>${esc(fieldName(c.obj,c.f))}</td><td>${showVal(c.obj,c.f,c.o)}</td><td>${showVal(c.obj,c.f,c.n)}</td><td class="small">${esc(nameOf(c.by))}</td>
    <td><span class="chip ${(ST[c.st]||['',''])[0]}">${esc((ST[c.st]||['',c.st])[1])}</span></td><td class="small">${c.dby?esc(nameOf(c.dby))+' · '+vdt(c.dat)+(c.note?'<br><span class="muted">'+esc(c.note)+'</span>':''):''}</td></tr>`).join('')}</tbody></table></div>`;
}

/* ---------- ME11 bảng giá mua ---------- */
function scrME11(){
  const m=md(S.co); const canC=can('ME11','C');
  const vs=vensOf(S.co), ms=matsOf(S.co).filter(x=>x.t==='HH'||x.t==='NVL');
  const rows=m.prices.slice().sort((a,b)=>(a.v+a.m).localeCompare(b.v+b.m)||String(b.from).localeCompare(String(a.from)));
  return `<div class="wrap">${head('ME11','Bảng giá mua (inforecord)','Đơn giá thỏa thuận theo nhà cung cấp và vật tư, có ngày hiệu lực. Khi lập đơn mua (ME21N), hệ thống đề xuất giá hiệu lực gần nhất; không có thì dùng giá tham khảo của vật tư.')}
  ${canC?`<form class="form panel" data-form="PRICE"><div class="err"></div><h2 style="margin:0">Cập nhật giá</h2>
   <div class="grid3"><label class="field"><span>Nhà cung cấp</span><select id="pr-v">${vs.filter(v=>v.active!==false).map(v=>`<option value="${esc(v.c)}">${esc(v.c)} · ${esc(v.n)}</option>`).join('')}</select></label>
   <label class="field"><span>Vật tư</span><select id="pr-m">${ms.filter(x=>x.active!==false).map(x=>`<option value="${esc(x.c)}">${esc(x.c)} · ${esc(x.n)}</option>`).join('')}</select></label>
   <label class="field"><span>Đơn giá (chưa VAT)</span><input id="pr-p" class="num" type="number" min="1" step="1" required></label>
   <label class="field"><span>Có hiệu lực từ</span><input id="pr-d" type="date" value="${today()}" required></label></div>
   <div class="form-foot"><span class="small muted">Cùng nhà cung cấp, vật tư và ngày hiệu lực thì giá mới thay giá cũ; nhật ký ZCHG lưu cả hai.</span><button class="btn pri">Lưu giá</button></div></form>`:''}
  <div class="tw"><table class="t"><thead><tr><th>Nhà cung cấp</th><th>Vật tư</th><th class="num">Đơn giá</th><th>Hiệu lực từ</th><th class="num">So với giá tham khảo</th></tr></thead><tbody>
  ${rows.map(p=>{const mm=mat(p.m);const d=mm.bp?(p.p-mm.bp)/mm.bp*100:0;return `<tr><td>${esc(p.v)} · ${esc((ven(p.v)||{n:''}).n)}</td><td>${esc(p.m)} · ${esc(mm.n)}</td><td class="num">${fm(p.p)}</td><td>${vd(String(p.from).slice(0,10))}</td><td class="num">${mm.bp?(d>0?'+':'')+d.toFixed(1)+'%':''}</td></tr>`;}).join('')||'<tr><td colspan="5" class="muted">Chưa có bảng giá.</td></tr>'}</tbody></table></div></div>`;
}

/* ---------- FS00 hệ thống tài khoản ---------- */
function scrFS00(){
  const A=S.acct||{}; const KIND={A:'Tài sản',L:'Nợ phải trả',E:'Vốn chủ sở hữu',R:'Doanh thu, thu nhập',X:'Chi phí',C:'Xác định kết quả'};
  const codes=Object.keys(A).sort();
  const q=(S.param&&S.param.q)||'';
  return `<div class="wrap">${head('FS00','Hệ thống tài khoản kế toán','Danh mục tài khoản theo Phụ lục II Thông tư 99/2025/TT-BTC (bản rút gọn dùng trong lab). Tài khoản đối chiếu (131, 331) chỉ ghi qua chứng từ nghiệp vụ, không hạch toán tay.')}
  <div class="note">${codes.length} tài khoản. Tên tài khoản lấy theo trích dẫn Phụ lục II – <b>CẦN GIẢNG VIÊN KIỂM TRA</b> lại với văn bản gốc trước khi dùng làm tài liệu chính thức.</div>
  <div class="tw"><table class="t"><thead><tr><th>Số hiệu</th><th>Tên tài khoản</th><th>Loại</th><th>Đối chiếu công nợ</th><th>Hạch toán tay</th><th>Cần trung tâm chi phí</th><th>Mở từ</th></tr></thead><tbody>
  ${codes.filter(k=>!q||k.startsWith(q)).map(k=>{const a=A[k];return `<tr><td class="mono" style="padding-left:${8+Math.max(0,k.length-3)*10}px">${esc(k)}</td><td>${esc(a.n)}</td><td class="small">${esc(KIND[a.k]||a.k||'')}</td><td>${a.r?esc(a.r):''}</td><td>${a.man===false?'Không':a.man?'Có':''}</td><td>${a.cc?'Có':''}</td><td class="small">${esc(a.ph||'')}</td></tr>`;}).join('')}</tbody></table></div></div>`;
}

/* ---------- ZORG cơ cấu tổ chức ---------- */
function scrZORG(){
  const org=md(S.co).org; const K={PLANT:'Nhà máy / địa điểm',SLOC:'Kho lưu trữ',PORG:'Tổ chức mua hàng',SORG:'Tổ chức bán hàng',DCHAN:'Kênh phân phối',CC:'Trung tâm chi phí',PC:'Trung tâm lợi nhuận'};
  const mem=Object.values(S.users).filter(u=>!u.is_admin&&u.co===S.co&&u.role);
  const depts={}; ROLE_ORDER.forEach(r=>{ const d=(ROLES[r]&&ROLES[r].dept)||'Khác'; (depts[d]=depts[d]||[]).push(r); });
  return `<div class="wrap">${head('ZORG','Cơ cấu tổ chức '+esc(S.co),'Đơn vị tổ chức dùng trên chứng từ (kho, tổ chức mua – bán, trung tâm chi phí, lợi nhuận) và phòng ban – vai trò trong công ty.')}
  <div class="cols"><div class="panel"><h2>Đơn vị tổ chức</h2>${Object.keys(K).map(k=>{const rs=org.filter(o=>o.k===k);return rs.length?`<h3 class="sec-title">${esc(K[k])}</h3><div class="tw"><table class="t"><tbody>${rs.map(o=>`<tr><td class="mono">${esc(o.c)}</td><td>${esc(o.n)}</td><td class="small muted">${esc(o.note||'')}${o.p?' · thuộc '+esc(o.p):''}</td></tr>`).join('')}</tbody></table></div>`:'';}).join('')}</div>
  <div class="panel"><h2>Phòng ban và vai trò</h2>${Object.keys(depts).map(d=>`<h3 class="sec-title">${esc(d)}</h3><ul class="small" style="margin:0 0 8px;padding-left:18px">${depts[d].map(r=>{const who=mem.filter(u=>userRoles(u).includes(r));return `<li><span class="dot" style="background:var(--r-${r})"></span> <b>${esc(ROLES[r].n)}</b> – ${esc(ROLES[r].d||'')}${who.length?' · <i>'+who.map(u=>esc(u.full_name)).join(', ')+'</i>':''}</li>`;}).join('')}</ul>`).join('')}</div></div></div>`;
}

/* ---------- ZMDA duyệt thay đổi dữ liệu gốc ---------- */
function scrZMDA(){
  const rows=md(S.co).chg.filter(c=>c.st==='pending');
  return `<div class="wrap">${head('ZMDA','Duyệt thay đổi dữ liệu gốc nhạy cảm','Tài khoản ngân hàng, thời hạn thanh toán, hạn mức tín dụng, khóa/mở đối tượng và việc tạo mới nhà cung cấp, khách hàng phải được người thứ hai duyệt. Người yêu cầu không được tự duyệt.')}
  ${rows.length?rows.map(c=>{const rec=c.obj==='MAT'||c.obj==='VEN'||c.obj==='CUS'?recOf(S.co,c.obj,c.key):null;const self=c.by===S.uid&&!S.isAdmin;
   return `<form class="form panel" data-form="MDDEC" data-id="${c.id}" style="gap:8px"><div class="err"></div>
    <div><b>${esc(OBJ_NAME[c.obj]||c.obj)} <span class="mono">${esc(c.key)}</span>${rec?' · '+esc(rec.n):''}</b> — ${esc(fieldName(c.obj,c.f))}</div>
    <dl class="kv"><dt>Giá trị hiện tại</dt><dd>${showVal(c.obj,c.f,c.o)}</dd><dt>Đề nghị đổi thành</dt><dd><b>${showVal(c.obj,c.f,c.n)}</b></dd>
     ${c.f==='*tạo mới'&&rec?`<dt>Mã số thuế</dt><dd class="mono">${esc(rec.mst)}</dd><dt>Tài khoản ngân hàng</dt><dd class="mono">${esc(rec.bank||'—')}</dd>`:''}
     <dt>Người yêu cầu</dt><dd>${esc(nameOf(c.by))} · ${vdt(c.at)}</dd></dl>
    ${c.f==='bank_acc'?'<div class="note warn small">Kiểm soát gợi ý: gọi lại số điện thoại đã lưu của nhà cung cấp (không dùng số trong thư yêu cầu) để xác nhận tài khoản mới trước khi duyệt.</div>':''}
    <label class="field"><span>Ghi chú / lý do (bắt buộc khi từ chối)</span><input id="f-note" maxlength="200"></label>
    <div style="display:flex;gap:8px">${self?'<span class="small muted">Bạn là người yêu cầu thay đổi này nên không thể duyệt.</span>':`<button class="btn pri sm" name="ok" value="1">Duyệt</button><button class="btn badb sm" name="ok" value="0">Từ chối</button>`}</div></form>`;}).join('')
   :`<div class="tw"><div class="empty">Không có thay đổi dữ liệu gốc nào đang chờ duyệt.</div></div>`}</div>`;
}

/* ---------- ZCHG nhật ký thay đổi ---------- */
function scrZCHG(){
  const f=(S.param&&S.param.obj)||'';
  const rows=md(S.co).chg.filter(c=>!f||c.obj===f);
  return `<div class="wrap">${head('ZCHG','Nhật ký thay đổi dữ liệu gốc','Ghi lại mọi lần tạo, sửa, duyệt, từ chối dữ liệu gốc (300 bản ghi gần nhất). Kiểm toán viên dùng nhật ký này để kiểm tra kiểm soát thay đổi.')}
  <div style="display:flex;gap:6px;flex-wrap:wrap">${[['','Tất cả'],['MAT','Vật tư'],['VEN','Nhà cung cấp'],['CUS','Khách hàng'],['PRICE','Bảng giá']].map(([k,l])=>`<button class="btn sm ${k===f?'pri':''}" data-go="ZCHG" data-p="${P({obj:k})}">${l}</button>`).join('')}</div>
  ${chgTable(rows,false)}</div>`;
}

/* ---------- Biểu mẫu ---------- */
const FORMS = {
  MDSAVE(f){ guard(f,async()=>{
    const obj=f.dataset.obj, key=f.dataset.key, O=OBJ[obj], rec=key?recOf(S.co,obj,key):null; const data={};
    for(const x of O.fields){ const el=f.querySelector('#md-'+x.f); if(!el||el.disabled) continue; let v=el.value.trim();
      if(x.req&&!v) return setErr(f,'<b>Thiếu '+esc(x.l.toLowerCase())+'.</b>');
      if(x.f==='mst'&&v&&!/^\d{10}(-\d{3})?$/.test(v)) return setErr(f,'<b>Mã số thuế phải có 10 chữ số</b> (hoặc 10 số và 3 số chi nhánh dạng 0123456789-001).');
      if(x.type==='num'&&v!==''&&!(Number(v)>=0)) return setErr(f,'<b>'+esc(x.l)+'</b> phải là số không âm.');
      if(rec&&String(rec[x.k]??'')===v) continue;
      if(rec&&x.type==='num'&&v!==''&&Number(rec[x.k])===Number(v)) continue;
      if(rec&&x.type==='date'&&String(rec[x.k]||'').slice(0,10)===v) continue;
      if(!rec&&v==='') continue;
      data[x.f]=v; }
    if(rec&&!Object.keys(data).length) return setErr(f,'<b>Chưa có trường nào thay đổi.</b>');
    const r=await api('erp_md_save',{p_token:S.token,p_co:S.co,p_obj:obj,p_key:key||'',p_data:data,p_act_role:actRole()});
    await sync();
    const pend=(r.pending||[]).filter(x=>x!=='*tạo mới').length;
    if(r.created) toast('Đã tạo '+O.n+' '+r.key+((r.pending||[]).includes('*tạo mới')?'. Chờ Kế toán trưởng xác nhận (ZMDA) trước khi dùng trên chứng từ.':'.'));
    else toast('Đã lưu '+((r.applied||[]).length)+' trường'+(pend?', '+pend+' trường nhạy cảm chờ Kế toán trưởng duyệt (ZMDA).':'.'));
    go(O.tc[2],{key:r.key||key});
  }); },
  MDDEC(f,e){ const ok=!!(e.submitter&&e.submitter.value==='1'); const note=val(f,'f-note');
    if(!ok&&!note) return setErr(f,'<b>Hãy ghi lý do từ chối.</b>');
    guard(f,async()=>{ await api('erp_md_decide',{p_token:S.token,p_co:S.co,p_id:+f.dataset.id,p_ok:ok,p_note:note,p_act_role:actRole()});
      await sync(); toast(ok?'Đã duyệt thay đổi.':'Đã từ chối thay đổi.'); render(true,true); }); },
  PRICE(f){ guard(f,async()=>{ const p=Math.round(num(val(f,'pr-p'))); if(!(p>0)) return setErr(f,'<b>Đơn giá phải lớn hơn 0.</b>');
    await api('erp_price_save',{p_token:S.token,p_co:S.co,p_vendor:val(f,'pr-v'),p_mat:val(f,'pr-m'),p_price:p,p_from:val(f,'pr-d'),p_act_role:actRole()});
    await sync(); toast('Đã lưu giá '+val(f,'pr-v')+' / '+val(f,'pr-m')+'.'); render(true,true); }); }
};

const MD = 'Dữ liệu gốc';
const tc = {
  'MM01':{m:MD,t:'Tạo vật tư',r:['MH'],pm:'MM01'},
  'MM02':{m:MD,t:'Thay đổi vật tư',r:['MH'],pm:'MM01'},
  'MM03':{m:MD,t:'Hiển thị vật tư',r:ALL},
  'XK01':{m:MD,t:'Tạo nhà cung cấp',r:['MH'],pm:'XK01'},
  'XK02':{m:MD,t:'Thay đổi nhà cung cấp',r:['MH'],pm:'XK01'},
  'XK03':{m:MD,t:'Hiển thị nhà cung cấp',r:ALL},
  'XD01':{m:MD,t:'Tạo khách hàng',r:['KD'],pm:'XD01'},
  'XD02':{m:MD,t:'Thay đổi khách hàng',r:['KD'],pm:'XD01'},
  'XD03':{m:MD,t:'Hiển thị khách hàng',r:ALL},
  'ME11':{m:MD,t:'Bảng giá mua',r:ALL},
  'FS00':{m:MD,t:'Hệ thống tài khoản',r:ALL},
  'ZORG':{m:MD,t:'Cơ cấu tổ chức',r:ALL},
  'ZMDA':{m:'Phê duyệt',t:'Duyệt thay đổi dữ liệu gốc',r:['KTT']},
  'ZCHG':{m:'Kiểm soát',t:'Nhật ký thay đổi dữ liệu gốc',r:['KTT','GD','KSNB']}
};
const screens = {ME11:scrME11,FS00:scrFS00,ZORG:scrZORG,ZMDA:scrZMDA,ZCHG:scrZCHG};
Object.keys(OBJ_OF_TC).forEach(t=>{ const x=OBJ_OF_TC[t]; screens[t]= x.mode==='show' ? ()=>mdShow(x.o) : ()=>mdForm(x.o,x.mode); });
Object.assign(LIVE_FORM,{MM01:1,XK01:1,XD01:1,ME11:1,ZMDA:1});
const isEdit = () => ['MM02','XK02','XD02'].includes(S.screen)&&S.param&&S.param.key;
// Màn hình thay đổi đang có dữ liệu nhập dở: không vẽ lại khi đồng bộ nền.
globalThis.MD_EDITING = isEdit;
erpModule({name:'P2 dữ liệu gốc',tc,screens,forms:FORMS});
globalThis.mdPendingCount = co => md(co).chg.filter(c=>c.st==='pending').length;
})();
