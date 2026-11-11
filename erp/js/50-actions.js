"use strict";
/* ERP Lab – Xử lý biểu mẫu, nút bấm, sự kiện. */
/* ============ FORM SUBMITS ============ */
function busy(f,on){ f.querySelectorAll('button').forEach(b=>b.disabled=on); }
async function guard(f,fn,pre){ busy(f,true); try{ await fn(); }catch(e){ console.error(e); setErr(f,(pre===''?'':'<b>'+(pre||'Không lưu được.')+'</b> ')+esc(dbErr(e))); } finally{ busy(f,false); } }
const val = (f,id) => (f.querySelector('#'+id)?.value||'').trim();

const FORM = {
  LOGIN(f){ guard(f,async()=>{ const r=await api('erp_login',{p_username:val(f,'l-user'),p_password:f.querySelector('#l-pass').value});
    S.token=r.token; LS.set('erp.token',r.token); await start(); },''); },
  PW(f){ guard(f,async()=>{ const o=f.querySelector('#p-old').value,n=f.querySelector('#p-new').value,n2=f.querySelector('#p-new2').value;
    if(n!==n2) return setErr(f,'<b>Hai lần nhập mật khẩu mới không khớp.</b>');
    await api('erp_change_password',{p_token:S.token,p_old:o,p_new:n}); toast('Đã đổi mật khẩu.'); await sync(); S.screen='HOME'; S.param=null; render(true); }); },
  IMPORT(f){ guard(f,async()=>{ const rows=parseRoster(f.querySelector('#i-rows').value);
    if(!rows.length) return setErr(f,'<b>Chưa có dòng hợp lệ.</b> Mỗi dòng cần MSSV và họ tên.');
    const r=await api('erp_admin_import',{p_token:S.token,p_rows:rows}); S.lastPw=(r.created||[]);
    toast('Đã tạo '+r.created.length+' tài khoản'+(r.skipped.length?', bỏ qua '+r.skipped.length+' MSSV đã có':'')+'.'); await sync(); render(true); }); },
  PR(f){ guard(f,async()=>{ const items=readLines(f,'PR'), reason=val(f,'f-reason');
    if(!reason) return setErr(f,'<b>Thiếu lý do đề nghị.</b>');
    if(items.some(i=>!(i.qty>0))) return setErr(f,'<b>Số lượng phải lớn hơn 0.</b>');
    if(new Set(items.map(i=>i.mat)).size!==items.length) return setErr(f,'<b>Trùng mặt hàng.</b> Gộp các dòng cùng mã hàng.');
    if(val(f,'f-need')<val(f,'f-date')) return setErr(f,'<b>Ngày cần hàng</b> phải sau ngày đề nghị.');
    const r=await createDoc(S.co,'PR',{status:'pending',date:val(f,'f-date'),need:val(f,'f-need'),reason,items});
    toast('Đã lưu đề nghị mua '+r.no+' và gửi Kế toán trưởng duyệt.'); go('DOC',{co:S.co,id:r.id}); }); },
  PO(f){ guard(f,async()=>{ const c=calc(S.co); const pr=c.by[f.dataset.pr];
    if(!pr||!c.Q.prForPO.includes(pr)) return setErr(f,'<b>Đề nghị mua này đã được lập đơn hoặc không còn hiệu lực.</b>');
    const vendor=val(f,'f-vendor'); const items=[...f.querySelectorAll('#polines tr')].map(tr=>({mat:tr.dataset.mat,qty:+tr.dataset.qty,price:Math.round(num(tr.querySelector('.po-price').value))}));
    if(items.some(i=>!(i.price>0))) return setErr(f,'<b>Đơn giá phải lớn hơn 0.</b>');
    const net=sum(items,i=>i.qty*i.price), vat=Math.round(net*VATR()), total=net+vat;
    // Tổng tiền, thuế và quyền tự duyệt do máy chủ tính lại; trình duyệt chỉ gửi đơn giá đã chọn.
    const r=await createDoc(S.co,'PO',{pr:pr.id,vendor,date:val(f,'f-date'),need:val(f,'f-need'),note:val(f,'f-note'),items});
    toast('Đã lưu đơn mua '+r.no+(r.status==='approved'?' (tự duyệt do dưới hạn mức).':', chờ Kế toán trưởng duyệt.')); go('DOC',{co:S.co,id:r.id}); }); },
  GR(f){ guard(f,async()=>{ const c=calc(S.co); const po=c.by[f.dataset.po]; const op=c.poOpen(po);
    const items=[...f.querySelectorAll('.gr-line')].map(tr=>{const i=+tr.dataset.i;return {line:i,mat:po.items[i].mat,qty:Math.round(num(tr.querySelector('.gr-qty').value)),price:po.items[i].price};}).filter(x=>x.qty>0);
    if(!items.length) return setErr(f,'<b>Chưa có số lượng thực nhận.</b>');
    const over=items.find(x=>x.qty>op[x.line]); if(over) return setErr(f,`<b>Nhập vượt đơn mua.</b> ${esc(over.mat)} chỉ còn ${op[over.line]} cần nhận. Hàng giao thừa phải lập biên bản và trả lại NCC.`);
    if(!val(f,'f-dn')||!val(f,'f-deliv')) return setErr(f,'<b>Thiếu số phiếu giao hàng hoặc người giao.</b>');
    // Bút toán Nợ 156 / Có 331 do máy chủ lập theo bảng xác định tài khoản.
    const r=await createDoc(S.co,'GR',{po:po.id,date:val(f,'f-date'),dn:val(f,'f-dn'),deliverer:val(f,'f-deliv'),items:items.map(x=>({line:x.line,qty:x.qty}))});
    toast('Đã ghi sổ phiếu nhập kho '+r.no+' (bút toán '+r.je+').'); go('DOC',{co:S.co,id:r.id}); }); },
  IV(f){ guard(f,async()=>{ const c=calc(S.co); const po=c.by[f.dataset.po]; const un=c.poUninv(po);
    const sym=val(f,'f-sym').toUpperCase(), no=val(f,'f-no');
    if(!sym||!no) return setErr(f,'<b>Thiếu ký hiệu hoặc số hóa đơn.</b>');
    if(c.T.IV.some(i=>i.status!=='rejected'&&i.vendor===po.vendor&&i.invSym===sym&&String(+i.invNo)===String(+no))) return setErr(f,'<b>Hóa đơn trùng.</b> Hóa đơn '+esc(sym)+'/'+esc(no)+' của nhà cung cấp này đã được ghi nhận.');
    const items=[...f.querySelectorAll('.iv-line')].map(tr=>{const i=+tr.dataset.i;return {line:i,mat:po.items[i].mat,qty:Math.round(num(tr.querySelector('.iv-qty').value)),price:Math.round(num(tr.querySelector('.iv-price').value)),poPrice:po.items[i].price};}).filter(x=>x.qty>0);
    if(!items.length) return setErr(f,'<b>Chưa có dòng nào trên hóa đơn.</b>');
    const over=items.find(x=>x.qty>un[x.line]); if(over) return setErr(f,`<b>Số lượng hóa đơn vượt số đã nhập kho.</b> ${esc(over.mat)} mới nhập ${un[over.line]} chưa có hóa đơn. Không ghi nhận hàng chưa về.`);
    const net=sum(items,x=>x.qty*x.price), vat=Math.round(net*VATR()), total=net+vat;
    if(Math.abs(num(val(f,'f-gross'))-total)>1) return setErr(f,`<b>Số liệu không cân.</b> Tổng trên hóa đơn ${fm(num(val(f,'f-gross')))} khác số hệ thống tính ${fm(total)}. Kiểm tra lại số lượng, đơn giá.`);
    // Máy chủ tự tính thuế, chênh lệch giá, khóa thanh toán khi lệch quá dung sai, và lập bút toán.
    const r=await createDoc(S.co,'IV',{po:po.id,invSym:sym,invNo:no,date:val(f,'f-date'),gross:num(val(f,'f-gross')),items:items.map(x=>({line:x.line,qty:x.qty,price:x.price}))});
    toast(r.status==='blocked'?'Hóa đơn '+r.no+' đã ghi sổ nhưng bị KHÓA THANH TOÁN do lệch giá.':'Đã ghi sổ hóa đơn '+r.no+'.'); go('DOC',{co:S.co,id:r.id}); }); },
  PAY(f){ guard(f,async()=>{ const c=calc(S.co); const iv=c.by[f.dataset.iv]; const rem=iv.total-c.ivPaid(iv)-c.ivPend(iv); const amt=Math.round(num(val(f,'f-amt')));
    if(iv.status!=='posted') return setErr(f,'<b>Hóa đơn đang bị khóa thanh toán.</b>');
    if(!(amt>0)||amt>rem+0.5) return setErr(f,`<b>Số tiền không hợp lệ.</b> Chỉ được đề nghị tối đa ${fm(rem)}.`);
    const r=await createDoc(S.co,'PAY',{iv:iv.id,date:val(f,'f-date'),acc:val(f,'f-acc'),amount:amt,memo:val(f,'f-memo')});
    toast('Đã gửi đề nghị chi '+r.no+' cho Kế toán trưởng.'); go('DOC',{co:S.co,id:r.id}); }); },
  SO(f){ guard(f,async()=>{ const items=readLines(f,'SO'); const cust=val(f,'f-cust');
    if(!val(f,'f-cpo')) return setErr(f,'<b>Thiếu số đơn đặt hàng của khách.</b> Đơn bán phải có căn cứ.');
    if(items.some(i=>!(i.qty>0)||!(i.price>0))) return setErr(f,'<b>Số lượng và đơn giá phải lớn hơn 0.</b>');
    if(new Set(items.map(i=>i.mat)).size!==items.length) return setErr(f,'<b>Trùng mặt hàng.</b>');
    // Kiểm tra tín dụng thực hiện trên máy chủ (dư nợ 131 + đơn đã xác nhận chưa xuất hóa đơn).
    const r=await createDoc(S.co,'SO',{cust,custPo:val(f,'f-cpo'),date:val(f,'f-date'),need:val(f,'f-need'),items});
    const blocked=r.status==='blocked';
    toast(blocked?'Đơn bán '+r.no+' bị KHÓA TÍN DỤNG, chờ Kế toán trưởng.':'Đơn bán '+r.no+' đã xác nhận, chuyển Thủ kho xuất hàng.'); go('DOC',{co:S.co,id:r.id}); }); },
  DL(f){ guard(f,async()=>{ const c=calc(S.co); const so=c.by[f.dataset.so]; const op=c.soOpen(so);
    if(so.status!=='approved') return setErr(f,'<b>Đơn bán chưa được xác nhận.</b>');
    const items=[...f.querySelectorAll('.dl-line')].map(tr=>{const i=+tr.dataset.i;return {line:i,mat:so.items[i].mat,qty:Math.round(num(tr.querySelector('.dl-qty').value))};}).filter(x=>x.qty>0);
    if(!items.length) return setErr(f,'<b>Chưa có số lượng xuất.</b>');
    for(const x of items){ if(x.qty>op[x.line]) return setErr(f,`<b>Xuất vượt đơn bán.</b> ${esc(x.mat)} chỉ còn ${op[x.line]}.`);
      if(x.qty>c.st[x.mat].q) return setErr(f,`<b>Không đủ tồn kho.</b> ${esc(x.mat)} chỉ còn ${c.st[x.mat].q} trong kho. Báo Thủ kho lập đề nghị mua (ME51N).`); }
    if(!val(f,'f-recv')) return setErr(f,'<b>Thiếu người nhận hàng.</b>');
    // Giá vốn bình quân di động và bút toán Nợ 632 / Có 156 do máy chủ tính.
    const r=await createDoc(S.co,'DL',{so:so.id,date:val(f,'f-date'),receiver:val(f,'f-recv'),vehicle:val(f,'f-veh'),items:items.map(x=>({line:x.line,qty:x.qty}))});
    toast('Đã ghi sổ phiếu xuất kho '+r.no+'.'); go('DOC',{co:S.co,id:r.id}); }); },
  BI(f){ guard(f,async()=>{ const c=calc(S.co); const dl=c.by[f.dataset.dl];
    if(c.kids('BI','dl',dl.id).length) return setErr(f,'<b>Phiếu xuất này đã được lập hóa đơn.</b>');
    // Số, ký hiệu hóa đơn, giá bán theo đơn bán, thuế và bút toán do máy chủ lập.
    const r=await createDoc(S.co,'BI',{dl:dl.id,date:val(f,'f-date')});
    toast('Đã phát hành hóa đơn '+r.no+'.'); go('DOC',{co:S.co,id:r.id}); }); },
  RC(f){ guard(f,async()=>{ const c=calc(S.co); const bi=c.by[f.dataset.bi]; const rem=bi.total-c.biPaid(bi)-c.biPend(bi); const amt=Math.round(num(val(f,'f-amt')));
    if(!(amt>0)||amt>rem+0.5) return setErr(f,`<b>Số tiền không hợp lệ.</b> Tối đa ${fm(rem)}.`);
    if(!val(f,'f-ref')) return setErr(f,'<b>Thiếu số giấy báo Có hoặc người nộp tiền.</b>');
    const r=await createDoc(S.co,'RC',{bi:bi.id,date:val(f,'f-date'),acc:val(f,'f-acc'),amount:amt,ref:val(f,'f-ref'),memo:'Thu tiền hóa đơn '+bi.invSym+' số '+bi.invNo});
    toast('Đã gửi phiếu thu '+r.no+' cho Kế toán trưởng.'); go('DOC',{co:S.co,id:r.id}); }); },
  DECIDE(f,ev){ const ok = ev&&ev.submitter ? ev.submitter.value==='1' : true;
    guard(f,async()=>{ const co=f.dataset.co, id=f.dataset.id; const c=calc(co); const d=c.by[id]; const note=val(f,'f-note');
    if(!allowed('SBWP')) return setErr(f,'<b>Không có quyền phê duyệt.</b>');
    if(d.by===S.uid&&!S.isAdmin&&!S.cfg.selfApprove) return setErr(f,'<b>Vi phạm bất kiêm nhiệm.</b> Bạn không thể phê duyệt chứng từ do chính mình lập. Nếu nhóm không còn ai khác được duyệt, báo giảng viên bật "Cho phép tự duyệt khi kiêm nhiệm" trong SPRO.');
    if(!ok&&!note) return setErr(f,'<b>Hãy ghi lý do từ chối</b> để người lập biết cần sửa gì.');
    if(ok&&d.type==='PAY'&&c.bal(d.acc)<d.amount) return setErr(f,`<b>Không đủ số dư TK ${d.acc}.</b> Số dư ${fm(c.bal(d.acc))}.`);
    if(!ok&&d.type==='IV') return setErr(f,'<b>Hóa đơn đã ghi sổ không hủy bằng từ chối.</b> Gỡ khóa khi nhà cung cấp xác nhận giá, hoặc chờ chức năng điều chỉnh hóa đơn (P4).');
    await api('erp_doc_decide',{p_token:S.token,p_co:co,p_id:id,p_ok:ok,p_note:note,p_act_role:S.isAdmin?S.role:''}); await sync(); toast(ok?'Đã phê duyệt '+d.no+'.':'Đã từ chối '+d.no+'.'); render(true,true); }); },
  EXTRA(f){ guard(f,async()=>{ const u=S.users[f.dataset.u]; if(!u) return;
    const ex=[...f.querySelectorAll('input[name="xr"]:checked,input[name="xg"]:checked')].map(i=>i.value);
    await api('erp_admin_assign',{p_token:S.token,p_rows:[{id:u.id,co:u.co,role:u.role,extra:ex}]}); S.editExtra=null; await sync(); toast('Đã lưu kiêm nhiệm cho '+u.full_name+'.'); render(true,true); }); },
  CFG(f){ guard(f,async()=>{ const cfg={tol:Math.max(0,num(val(f,'c-tol'))),poAuto:Math.max(0,num(val(f,'c-po'))),credit:val(f,'c-cr')==='1',selfApprove:val(f,'c-self')==='1',vat:val(f,'c-vat')};
    await api('erp_admin_set_cfg',{p_token:S.token,p_cfg:cfg}); await sync(); toast('Đã lưu tham số.'); }); }
};

/* ============ ACTIONS ============ */
const ACT = {
  back(){ back(); },
  menu(){ document.getElementById('side').classList.toggle('open'); },
  addLine(a){ const tb=document.getElementById('lines'); const nm=lineMats(a.dataset.kind,S.co).length; if(tb.children.length>=nm) return toast('Tối đa '+nm+' dòng.'); tb.insertAdjacentHTML('beforeend',lineRow(a.dataset.kind,S.co)); const f=a.closest('form'); CALC[f.dataset.calc](f); },
  delLine(a){ const tb=document.getElementById('lines'); if(tb.children.length<=1) return; const f=a.closest('form'); a.closest('tr').remove(); CALC[f.dataset.calc](f); },
  viewCo(a){ LS.set('erp.co',a.dataset.co); S.co=a.dataset.co; S.sideKey=''; go('HOME'); },
  editExtra(a){ S.editExtra = S.editExtra===a.dataset.u ? null : a.dataset.u; render(true,true); },
  async autoAssign(){ const us=Object.values(S.users).filter(u=>!u.is_admin);
    const todo=us.filter(u=>!u.co||!u.role); if(!todo.length) return toast('Không còn sinh viên chờ phân công.');
    const mem={}; COS.forEach(c=>mem[c]=us.filter(u=>u.co&&u.role&&u.co===c).map(u=>({id:u.id,role:u.role,extra:(u.extra||[]).slice(),old:true})));
    todo.sort((a,b)=>String(a.username).localeCompare(String(b.username))).forEach(u=>{ let co=u.grp&&COS[u.grp-1]?COS[u.grp-1]:null;
      if(!co||mem[co].length>=5) co=COS.slice().sort((a,b)=>mem[a].length-mem[b].length)[0];
      mem[co].push({id:u.id,role:null,extra:[],old:false}); });
    const FILL=['KHO','KT','KTT','MH','KD']; const rows=[];
    COS.forEach(co=>{ const m=mem[co]; if(!m.some(x=>!x.old)) return;
      m.filter(x=>!x.old).forEach(x=>{ const held=new Set(m.filter(y=>y.role).map(y=>y.role)); x.role=FILL.find(r=>!held.has(r))||FILL.find(r=>true); });
      m.forEach(y=>{ const k=y.extra.filter(e=>e.startsWith('T:')); if(k.length!==y.extra.length){ y.extra=k; y.touched=true; } });
      if(m.length<5){ const held=new Set(); m.forEach(y=>{held.add(y.role); y.extra.forEach(e=>held.add(e));});
        FILL.filter(r=>!held.has(r)).forEach(r=>{ const cand=m.filter(y=>!(m.length>=3&&y.role==='KTT'));
          const score=y=>{const rs=[y.role].concat(y.extra.filter(e=>ROLES[e])); return sum(rs,q=>conflictOf(q,r))+1.5*rs.length;};
          const pick=(cand.length?cand:m).slice().sort((a,b)=>score(a)-score(b))[0]; pick.extra.push(r); pick.touched=true; }); }
      m.forEach(x=>{ if(!x.old||x.touched) rows.push({id:x.id,co,role:x.role,extra:x.extra}); }); });
    try{ await api('erp_admin_assign',{p_token:S.token,p_rows:rows}); await sync(); toast('Đã phân công '+todo.length+' sinh viên. Nhóm thiếu người đã được giao kiêm nhiệm.'); render(true,true);}catch(e){ toast(dbErr(e)); } },
  async applyPack(a){ const pk=document.getElementById('pk-code').value, co=document.getElementById('pk-co').value;
    if(a.dataset.sure!=='1'){ a.dataset.sure='1'; a.textContent='Bấm lần nữa để áp '+pk+(co?' cho '+co:' cho cả 8 công ty'); setTimeout(()=>{a.dataset.sure='';a.textContent='Áp gói';},4000); return; }
    a.disabled=true;
    try{ const r=await api('erp_admin_apply_pack',{p_token:S.token,p_pack:pk,p_co:co}); await sync(); toast('Đã áp gói '+pk+' cho '+Object.keys(r||{}).length+' công ty.'); render(true,true);}catch(e){ toast(dbErr(e)); a.disabled=false; } },
  async rotate(a){ if(a.dataset.sure!=='1'){ a.dataset.sure='1'; a.textContent='Bấm lần nữa để xoay vòng'; setTimeout(()=>{a.dataset.sure='';a.textContent='Xoay vòng vai trò';},4000); return; }
    const rows=[];
    COS.forEach(co=>{ const m=Object.values(S.users).filter(u=>!u.is_admin&&u.co===co&&u.role).sort((x,y)=>ROLE_ORDER.indexOf(x.role)-ROLE_ORDER.indexOf(y.role));
      m.forEach((u,i)=>{ const nx=m[(i+1)%m.length]; rows.push({id:u.id,co,role:nx.role,extra:(nx.extra||[]).slice()}); }); });
    try{ await api('erp_admin_assign',{p_token:S.token,p_rows:rows}); await sync(); toast('Đã xoay vòng: mỗi bạn nhận phần việc (cả kiêm nhiệm) của bạn kế tiếp trong nhóm.'); render(true,true);}catch(e){ toast(dbErr(e)); } },
  async resetPw(a){ if(a.dataset.sure!=='1'){ a.dataset.sure='1'; a.textContent='Xác nhận?'; setTimeout(()=>{a.dataset.sure='';a.textContent='Cấp lại MK';},4000); return; }
    try{ const r=await api('erp_admin_reset_pw',{p_token:S.token,p_user:a.dataset.u}); S.lastPw=[r]; await sync(); render(true,true); toast('Đã cấp lại mật khẩu cho '+r.mssv+'.'); }catch(e){ toast(dbErr(e)); } },
  async delUser(a){ if(a.dataset.sure!=='1'){ a.dataset.sure='1'; a.textContent='Xóa thật?'; setTimeout(()=>{a.dataset.sure='';a.textContent='Xóa';},4000); return; }
    try{ await api('erp_admin_delete_user',{p_token:S.token,p_user:a.dataset.u}); await sync(); render(true,true); toast('Đã xóa tài khoản.'); }catch(e){ toast(dbErr(e)); } },
  dlPw(){ const rows=[['MSSV','Ho ten','Mat khau']].concat((S.lastPw||[]).map(x=>[x.mssv,x.name,x.password]));
    const csv='\ufeff'+rows.map(r=>r.map(v=>'"'+String(v).replace(/"/g,'""')+'"').join(',')).join('\r\n');
    const a=document.getElementById('dl'); a.href=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'})); a.download='erp-mat-khau-'+today()+'.csv'; a.click(); },
  async copyPw(){ const t=(S.lastPw||[]).map(x=>[x.mssv,x.name,x.password].join('\t')).join('\n'); try{ await navigator.clipboard.writeText(t); toast('Đã chép bảng mật khẩu.'); }catch(e){ toast('Không chép được, hãy dùng nút Tải CSV.'); } },
  clearPw(){ S.lastPw=null; render(true,true); },
  logout(){ logout(); },
  peekCase(){ S.peek=scrCase; render(true,true); },
  peekPfcg(){ S.peek=scrPFCG; render(true,true); },
  resetAsk(){ const co=document.getElementById('c-reset').value; document.getElementById('reset-confirm').innerHTML=`<button class="btn sm badb" data-act="resetDo" data-co="${co}">Xác nhận xóa toàn bộ chứng từ ${co}</button>`; },
  async resetDo(a){ const co=a.dataset.co; a.disabled=true; try{ const n=await api('erp_admin_reset_co',{p_token:S.token,p_co:co}); await sync(true); toast('Đã xóa '+n+' chứng từ của '+co+'.'); render(true); }catch(e){ toast(dbErr(e)); a.disabled=false; } }
};
const CHG = {
  co(s){ LS.set('erp.co',s.value); S.sideKey=''; render(true); },
  role(s){ LS.set('erp.role',s.value); S.sideKey=''; render(true); },
  linemat(s){ const tr=s.closest('tr'); const p=tr.querySelector('.li-price'); if(p) p.value=mat(s.value).sp; const f=s.closest('form'); CALC[f.dataset.calc](f); },
  povendor(s){ const f=s.closest('form'); const d=(f.querySelector('#f-date')||{}).value; f.querySelectorAll('#polines tr').forEach(tr=>{tr.querySelector('.po-price').value=priceOf(S.co,s.value,tr.dataset.mat,d).p;}); CALC.PO(f); },
  socust(s){ CALC.SO(s.closest('form')); },
  async asgCo(s){ const u=S.users[s.dataset.u]||{}; const co=s.value||null; const role=co?(u.role||'KHO'):null;
    try{ await api('erp_admin_assign',{p_token:S.token,p_rows:[{id:s.dataset.u,co,role}]}); await sync(); render(true,true);}catch(e){toast(dbErr(e));} },
  async asgRole(s){ const u=S.users[s.dataset.u]||{}; const role=s.value||null; const co=role?(u.co||(u.grp&&COS[u.grp-1])||'C01'):u.co;
    try{ await api('erp_admin_assign',{p_token:S.token,p_rows:[{id:s.dataset.u,co,role}]}); await sync(); render(true,true);}catch(e){toast(dbErr(e));} }
};

document.addEventListener('click',e=>{
  const g=e.target.closest('[data-go]'); if(g){ e.preventDefault(); let p=null; try{p=g.dataset.p?JSON.parse(g.dataset.p):null;}catch(x){} go(g.dataset.go,p); return; }
  const a=e.target.closest('[data-act]'); if(a&&ACT[a.dataset.act]){ e.preventDefault(); ACT[a.dataset.act](a,e); }
});
document.addEventListener('submit',e=>{ const f=e.target.closest('form[data-form]'); if(f){ e.preventDefault(); FORM[f.dataset.form](f,e); } });
document.addEventListener('input',e=>{ const f=e.target.closest('form[data-calc]'); if(f&&CALC[f.dataset.calc]) CALC[f.dataset.calc](f);
  if(e.target.id==='i-rows'){ const n=parseRoster(e.target.value).length; document.getElementById('i-preview').textContent=n?n+' dòng hợp lệ':''; } });
document.addEventListener('change',e=>{ const s=e.target.closest('[data-chg]'); if(s&&CHG[s.dataset.chg]) CHG[s.dataset.chg](s); });
document.getElementById('cmdform').addEventListener('submit',e=>{ e.preventDefault(); const i=document.getElementById('cmd'); let v=i.value.trim().toUpperCase().replace(/^\/[NO]\s*/,''); i.value=''; if(v) go(v); });

