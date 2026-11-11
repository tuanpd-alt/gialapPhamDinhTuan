"use strict";
/* ERP Lab – Lõi: trạng thái, tiện ích, sổ dẫn xuất để hiển thị, gọi API, phân quyền, đồng bộ, điều hướng. */
/* ============ ĐĂNG KÝ PHÂN HỆ ============ */
// Mỗi phân hệ mới (P2 trở đi) là một tệp js/mod-*.js gọi erpModule({...}) để thêm T-code, màn hình, biểu mẫu.
// Ví dụ: erpModule({ tc:{'FS00':{m:'Kế toán (FI)',t:'Hệ thống tài khoản',r:['KTT']}}, screens:{'FS00':scrFS00}, forms:{FS00(f){…}} });
const SCREENS = {};
const MODULES = [];
function erpModule(m){
  MODULES.push(m.name||'?');
  if(m.tc) Object.assign(TC, m.tc);
  if(m.screens) Object.assign(SCREENS, m.screens);
  if(m.forms) Object.assign(FORM, m.forms);
  if(m.acts) Object.assign(ACT, m.acts);
  if(m.chg) Object.assign(CHG, m.chg);
  if(m.calc) Object.assign(CALC, m.calc);
}

/* ============ STATE ============ */
const CFG = window.ERP_CONFIG || {};
const S = {token:null,me:null,uid:null,isAdmin:false,users:{},md:{},auth:null,acct:null,cfg:{tol:5,poAuto:0,credit:true},docs:{},ver:{},
  since:null,epochs:{},metaKey:'',co:null,role:null,screen:'HOME',param:null,stack:[],sideKey:'',lastPw:null,timer:null,online:true};
const LS = {get(k){try{return localStorage.getItem(k)}catch(e){return null}},set(k,v){try{localStorage.setItem(k,v)}catch(e){}},del(k){try{localStorage.removeItem(k)}catch(e){}}};

/* ============ UTIL ============ */
const esc = s => String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const NF = new Intl.NumberFormat('vi-VN');
const fm = n => NF.format(Math.round(n||0));
const pad = (n,l) => String(n).padStart(l,'0');
const now = () => new Date().toISOString();
function today(){const d=new Date();return d.getFullYear()+'-'+pad(d.getMonth()+1,2)+'-'+pad(d.getDate(),2)}
function addDays(s,n){const d=new Date(s+'T00:00:00');d.setDate(d.getDate()+n);return d.getFullYear()+'-'+pad(d.getMonth()+1,2)+'-'+pad(d.getDate(),2)}
const vd = s => s ? s.split('-').reverse().join('/') : '';
const vdt = s => { if(!s) return ''; const d=new Date(s); return pad(d.getDate(),2)+'/'+pad(d.getMonth()+1,2)+' '+pad(d.getHours(),2)+':'+pad(d.getMinutes(),2); };
const num = v => { const n = Number(String(v).replace(/[^\d.-]/g,'')); return isFinite(n)?n:0; };
const sum = (a,f) => a.reduce((s,x)=>s+(f?f(x):x),0);
const P = o => esc(JSON.stringify(o));

function docSo(n){
  n=Math.round(Math.abs(n)); if(n===0) return 'Không đồng';
  const cs=['không','một','hai','ba','bốn','năm','sáu','bảy','tám','chín'];
  const r3=(x,full)=>{const tr=Math.floor(x/100),ch=Math.floor(x%100/10),dv=x%10,s=[];
    if(full||tr>0) s.push(cs[tr]+' trăm');
    if(ch===0){ if(dv>0&&(full||tr>0)) s.push('lẻ'); }
    else if(ch===1) s.push('mười'); else s.push(cs[ch]+' mươi');
    if(dv>0){ if(dv===1&&ch>1) s.push('mốt'); else if(dv===5&&ch>0) s.push('lăm'); else s.push(cs[dv]); }
    return s.join(' ');};
  const u=['','nghìn','triệu','tỷ','nghìn tỷ','triệu tỷ']; const g=[];
  while(n>0){g.push(n%1000);n=Math.floor(n/1000);}
  const out=[]; for(let i=g.length-1;i>=0;i--){ if(g[i]===0) continue; out.push(r3(g[i],i<g.length-1)+(u[i]?' '+u[i]:'')); }
  const s=out.join(' ').replace(/\s+/g,' ').trim(); return s.charAt(0).toUpperCase()+s.slice(1)+' đồng.';
}

function nameOf(uid){
  if(!uid) return '—';
  const u=S.users[uid]; if(u&&u.full_name) return u.full_name;
  return 'Người dùng đã bị xóa';
}
function toast(msg){ const t=document.getElementById('toast'); t.textContent=msg; t.hidden=false; clearTimeout(toast.t); toast.t=setTimeout(()=>t.hidden=true,4200); }

/* ============ DERIVED LEDGER ============ */
const memo = {};
function calc(co){
  const v = S.ver[co]||0;
  if(memo[co] && memo[co].v===v) return memo[co].c;
  const D = S.docs[co]||{};
  const L = Object.keys(D).map(id=>Object.assign({id},D[id]));
  L.sort((a,b)=>String(a.at||'').localeCompare(String(b.at||'')));
  const T = {}; Object.keys(TYPES).forEach(t=>T[t]=[]);
  L.forEach(d=>{ if(T[d.type]) T[d.type].push(d); });
  const live = d => d.status!=='rejected';
  const by = {}; L.forEach(d=>by[d.id]=d);
  const kids = (t,f,id) => T[t].filter(x=>x[f]===id&&live(x));

  const st = {}; const S0 = c => st[c] || (st[c]={oq:0,ov:0,iq:0,xq:0,v:0,mv:[]});
  matsOf(co).forEach(m=>S0(m.c));
  T.GR.filter(live).forEach(g=>g.items.forEach(it=>{const x=S0(it.mat); x.iq+=it.qty; x.mv.push({d:g,q:it.qty});}));
  T.DL.filter(live).forEach(g=>g.items.forEach(it=>{const x=S0(it.mat); x.xq+=it.qty; x.mv.push({d:g,q:-it.qty});}));

  const acc = {}; Object.keys(ACCS).forEach(a=>acc[a]={o:0,dr:0,cr:0});
  const ap = {}, ar = {}; vensOf(co).forEach(x=>ap[x.c]={dr:0,cr:0}); custsOf(co).forEach(x=>ar[x.c]={dr:0,cr:0});
  const P0 = (o,k) => o[k] || (o[k]={dr:0,cr:0});
  const lines = [];
  L.forEach(d=>{ if(!live(d)||!Array.isArray(d.je)) return; d.je.forEach(j=>{
    const a=acc[j.a]; if(!a) return;
    const inv = INV_ACCS.includes(j.a)&&j.mat;
    if(d.type==='OB'){ a.o+=(j.dr||0)-(j.cr||0); if(inv){ const x=S0(j.mat); x.oq+=j.q||0; x.ov+=j.dr||0; x.v+=j.dr||0; } return; }
    a.dr+=j.dr||0; a.cr+=j.cr||0;
    if(inv) S0(j.mat).v+=(j.dr||0)-(j.cr||0);
    if(j.a==='331'&&j.p){const x=P0(ap,j.p); x.dr+=j.dr||0; x.cr+=j.cr||0;}
    if(j.a==='131'&&j.p){const x=P0(ar,j.p); x.dr+=j.dr||0; x.cr+=j.cr||0;}
    lines.push({d,j}); }); });
  Object.keys(st).forEach(k=>{const s=st[k]; s.q=s.oq+s.iq-s.xq; s.avg=s.q>0?s.v/s.q:(mat(k,co).oc||mat(k,co).bp||0);});
  const bal = a => acc[a]?acc[a].o+acc[a].dr-acc[a].cr:0;

  // P2P open quantities
  const poOpen = po => po.items.map((it,i)=>it.qty-sum(kids('GR','po',po.id),g=>sum(g.items.filter(x=>x.line===i),x=>x.qty)));
  const poUninv = po => po.items.map((it,i)=>sum(kids('GR','po',po.id),g=>sum(g.items.filter(x=>x.line===i),x=>x.qty))-sum(kids('IV','po',po.id),g=>sum(g.items.filter(x=>x.line===i),x=>x.qty)));
  const ivPaid = iv => sum(T.PAY.filter(p=>p.iv===iv.id&&p.status==='posted'),p=>p.amount);
  const ivPend = iv => sum(T.PAY.filter(p=>p.iv===iv.id&&p.status==='pending'),p=>p.amount);
  // O2C
  const soDeliv = so => so.items.map((it,i)=>sum(kids('DL','so',so.id),g=>sum(g.items.filter(x=>x.line===i),x=>x.qty)));
  const soOpen = so => { const dv=soDeliv(so); return so.items.map((it,i)=>it.qty-dv[i]); };
  const soBilled = so => so.items.map((it,i)=>sum(kids('BI','so',so.id),g=>sum(g.items.filter(x=>x.line===i),x=>x.qty)));
  const biPaid = bi => sum(T.RC.filter(p=>p.bi===bi.id&&p.status==='posted'),p=>p.amount);
  const biPend = bi => sum(T.RC.filter(p=>p.bi===bi.id&&p.status==='pending'),p=>p.amount);
  const exposure = c => { const r0=P0(ar,c); const arb=r0.dr-r0.cr; const openSO=sum(T.SO.filter(s=>s.cust===c&&s.status==='approved'),s=>{const b=soBilled(s);return sum(s.items.map((it,i)=>(it.qty-b[i])*it.price*(1+VATR())));}); return {ar:Math.round(arb),so:Math.round(openSO),tot:Math.round(arb+openSO)}; };

  const Q = {
    prForPO: T.PR.filter(p=>p.status==='approved'&&kids('PO','pr',p.id).length===0),
    poForGR: T.PO.filter(p=>p.status==='approved'&&poOpen(p).some(q=>q>0)),
    poForIV: T.PO.filter(p=>p.status==='approved'&&poUninv(p).some(q=>q>0)),
    ivForPay: T.IV.filter(i=>i.status==='posted'&&i.total-ivPaid(i)-ivPend(i)>0.5),
    soForDL: T.SO.filter(s=>s.status==='approved'&&soOpen(s).some(q=>q>0)),
    dlForBI: T.DL.filter(d=>d.status==='posted'&&kids('BI','dl',d.id).length===0),
    biForRC: T.BI.filter(b=>b.status==='posted'&&b.total-biPaid(b)-biPend(b)>0.5),
    ap: {PR:T.PR.filter(x=>x.status==='pending'),PO:T.PO.filter(x=>x.status==='pending'),IV:T.IV.filter(x=>x.status==='blocked'),
         SO:T.SO.filter(x=>x.status==='blocked'),PAY:T.PAY.filter(x=>x.status==='pending'),RC:T.RC.filter(x=>x.status==='pending')}
  };
  Q.apAll = [].concat(Q.ap.PR,Q.ap.PO,Q.ap.IV,Q.ap.SO,Q.ap.PAY,Q.ap.RC);
  const c = {L,T,by,kids,st,acc,ap,ar,lines,bal,poOpen,poUninv,ivPaid,ivPend,soOpen,soDeliv,soBilled,biPaid,biPend,exposure,Q};
  memo[co] = {v,c}; return c;
}

/* ============ API (Supabase RPC) ============ */
async function api(fn,args){
  let res;
  try{
    res = await fetch(CFG.supabaseUrl.replace(/\/+$/,'')+'/rest/v1/rpc/'+fn,{method:'POST',
      headers:{'Content-Type':'application/json','apikey':CFG.supabaseAnonKey,'Authorization':'Bearer '+CFG.supabaseAnonKey},
      body:JSON.stringify(args||{})});
  }catch(e){ const er=new Error('Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.'); er.code='net'; throw er; }
  const txt = await res.text(); let j=null; try{ j=txt?JSON.parse(txt):null; }catch(e){}
  if(!res.ok){ const er=new Error((j&&j.message)||('Lỗi máy chủ '+res.status)); er.code=j&&j.code; er.status=res.status; throw er; }
  return j;
}
async function createDoc(co,type,body,note){
  const r = await api('erp_doc_create',{p_token:S.token,p_co:co,p_type:type,p_body:body,p_note:note||'',p_act_role:S.isAdmin?S.role:''});
  await sync(); return r;
}
function dbErr(e){
  if(e&&e.code==='28000'){ setTimeout(logout,50); return 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.'; }
  return (e&&e.message)||'Không lưu được, hãy thử lại.';
}
/* ============ AUTHORIZATION ============ */
const TC_DOC = {'ME51N':'PR','ME21N':'PO','MIGO':'GR','MIRO':'IV','F-53':'PAY','VA01':'SO','VL01N':'DL','VF01':'BI','F-28':'RC'};
// Vai trò lập từng loại chứng từ (khớp erp_type_role trên máy chủ). KT = AP + AR.
const TYPE_ROLE = {PR:'KHO',GR:'KHO',DL:'KHO',PO:'MH',SO:'KD',IV:'AP',PAY:'AP',BI:'AR',RC:'AR'};
const GRANTS = ['PR','PO','GR','IV','PAY','SO','DL','BI','RC','AP'];
const grantName = g => g==='AP' ? 'Phê duyệt chứng từ' : TYPES[g].n+' ('+TYPES[g].tc+')';
// Ma trận xung đột dự phòng; erp_sync (auth.conflict) trả về bảng đầy đủ từ erp_conflict() trên máy chủ (SPEC 4.3).
const CONFLICT0 = {'KHO|MH':[2,'Tự đặt mua và tự nhận hàng'],'KHO|KT':[3,'Vừa giữ hàng vừa ghi sổ'],'KHO|AP':[3,'Vừa giữ hàng vừa ghi sổ'],'KHO|AR':[3,'Vừa giữ hàng vừa ghi sổ'],
  'KHO|KD':[1,'Vừa bán vừa xuất kho'],'MH|KT':[2,'Tự đặt mua và tự đề nghị trả tiền'],'MH|AP':[2,'Tự đặt mua và tự đề nghị trả tiền'],'KD|KT':[2,'Tự bán và tự xóa nợ'],'KD|AR':[2,'Tự bán và tự xóa nợ'],
  'TQ|TH':[3,'Giữ tiền và ghi sổ'],'TQ|AP':[3,'Giữ tiền và ghi sổ'],'TQ|AR':[3,'Giữ tiền và ghi sổ'],'TQ|KT':[3,'Giữ tiền và ghi sổ']};
function conflictRec(a,b){
  if(!a||!b||a===b) return null;
  const C=S.auth&&S.auth.conflict; const k1=a<b?a+'|'+b:b+'|'+a;
  if(C) return C[k1]?{s:C[k1].s,w:C[k1].w||''}:null;
  const x=CONFLICT0[a+'|'+b]||CONFLICT0[b+'|'+a]; if(x) return {s:x[0],w:x[1]};
  if((a==='KTT'||b==='KTT')&&a!=='GD'&&b!=='GD'&&a!=='KSNB'&&b!=='KSNB') return {s:3,w:'Vừa lập vừa phê duyệt'};
  if((a==='KSNB'||b==='KSNB')&&a!=='GD'&&b!=='GD') return {s:3,w:'Kiểm toán nội bộ phải độc lập với đối tượng được kiểm tra'};
  return null;
}
const conflictOf = (a,b) => (conflictRec(a,b)||{s:0}).s;
const conflictWhy = (a,b) => (conflictRec(a,b)||{w:''}).w;
function userRoles(u){ if(!u||!u.role) return []; return [u.role].concat((u.extra||[]).filter(x=>ROLES[x]&&x!==u.role)); }
function userGrants(u){ return ((u&&u.extra)||[]).filter(x=>x.startsWith('T:')).map(x=>x.slice(2)); }
function myRoles(){ if(S.isAdmin) return S.role==='GV'?ROLE_ORDER.slice():[S.role]; return userRoles(S.me); }
function myGrants(){ return S.isAdmin?[]:userGrants(S.me); }
// KT (vai trò gộp của bản 1) được hiểu là AP + AR, giống erp_expand() trên máy chủ.
function expandRoles(rs){ const o=new Set(rs); if(o.has('KT')){ o.add('AP'); o.add('AR'); } return [...o]; }
const permTc = tc => (TC[tc]&&TC[tc].pm)||tc;
// Quyền theo bảng erp_role_perm (C = lập/thay đổi, A = phê duyệt, V = xem). Chưa đồng bộ thì dùng danh sách r trong TC.
function roleCan(roles,tc,act){
  const P=S.auth&&S.auth.perms; const rs=expandRoles(roles); const k=permTc(tc);
  if(!P){ const t=TC[tc]; return !!t&&Array.isArray(t.r)&&t.r.some(r=>rs.includes(r)); }
  return rs.some(r=>(P[r]||[]).some(x=>x.tc===k&&(!act||x.a===act)));
}
function can(tc,act){ if(S.isAdmin&&S.role==='GV') return true; return roleCan(myRoles(),tc,act); }
function canApprove(){ return myGrants().includes('AP') || can('SBWP','A'); }
function allowed(tc){
  const t = TC[tc]; if(!t) return false;
  if(t.admin) return S.isAdmin;
  if(S.role==='GV') return true;
  if(t.r===ALL) return true;
  if('ap' in t) return canApprove();
  const dt = TC_DOC[tc];
  if(dt && myGrants().includes(dt)) return true;
  return can(tc);
}
function rolesLabel(u){ const rs=userRoles(u); if(!rs.length) return '—'; const g=userGrants(u);
  return roleName(rs[0]) + (rs.length>1?' · kiêm '+rs.slice(1).map(roleName).join(', '):'') + (g.length?' · được giao: '+g.map(x=>x==='AP'?'phê duyệt':TYPES[x].tc).join(', '):''); }
function userConflicts(u){ const rs=userRoles(u), out=[]; for(let i=0;i<rs.length;i++) for(let j=i+1;j<rs.length;j++){ const sc=conflictOf(rs[i],rs[j]); if(sc>=2) out.push({a:rs[i],b:rs[j],sc}); } return out; }
function rolesFor(tc){ const t=TC[tc]; if(!t) return ''; if(t.admin) return 'Giảng viên'; if(t.r===ALL) return 'Tất cả';
  const rs=ROLE_ORDER.filter(r=>r!=='KT'&&roleCan([r],tc)); if(rs.includes('AP')||rs.includes('AR')) rs.push('KT');
  return rs.length?rs.map(roleName).join(', '):'Chưa mở ở giai đoạn này'; }

/* ============ STATUS LABELS ============ */
function stLabel(d){
  const s=d.status;
  const map = {
    PR:{pending:'Chờ duyệt',approved:'Đã duyệt',rejected:'Từ chối'},
    PO:{pending:'Chờ duyệt',approved:'Đã duyệt',rejected:'Từ chối'},
    GR:{posted:'Đã nhập kho'}, DL:{posted:'Đã xuất kho'},
    IV:{posted:'Đã ghi sổ',blocked:'Khóa thanh toán',rejected:'Đã hủy'},
    PAY:{pending:'Chờ duyệt chi',posted:'Đã chi',rejected:'Từ chối'},
    SO:{approved:'Đã xác nhận',blocked:'Khóa tín dụng',rejected:'Từ chối'},
    BI:{posted:'Đã ghi sổ'},
    RC:{pending:'Chờ duyệt thu',posted:'Đã thu',rejected:'Từ chối'}
  };
  return (map[d.type]&&map[d.type][s])||s;
}
const chip = d => `<span class="chip c-${esc(d.status)}">${esc(stLabel(d))}</span>`;
function partnerOf(d){ if(d.vendor) return ven(d.vendor)?.n||d.vendor; if(d.cust) return cus(d.cust)?.n||d.cust; return '—'; }
function valueOf(d){ if(d.total!=null) return d.total; if(d.amount!=null) return d.amount; if(d.value!=null) return d.value;
  if(d.type==='PR') return sum(d.items,it=>it.qty*mat(it.mat).bp); if(d.type==='DL') return sum(d.items,it=>it.cost||0); return 0; }
const docLink = (co,d,label) => `<button class="linkbtn mono" data-go="DOC" data-p="${P({co,id:d.id})}">${esc(label||d.no)}</button>`;

/* ============ CONTEXT & SYNC ============ */
function ctxResolve(){
  if(S.isAdmin){
    const c=LS.get('erp.co'); S.co = c&&COS.includes(c) ? c : (S.co||'C01');
    const r = LS.get('erp.role'); S.role = (r&&(r==='GV'||ROLES[r]))?r:'GV';
  } else {
    S.co = S.me&&S.me.co||null; S.role = S.me&&S.me.role||null;
  }
}
let syncing=null;
async function sync(full){
  while(syncing){ try{ await syncing; }catch(e){} }
  syncing = (async()=>{
    const r = await api('erp_sync',{p_token:S.token,p_co:'*',p_since:full?null:S.since});
    const before = S.me?JSON.stringify([S.me.co,S.me.role]):null;
    S.me=r.me; S.uid=r.me.id; S.isAdmin=!!r.me.is_admin;
    if(r.accts){ S.acct=r.accts; Object.keys(r.accts).forEach(k=>{ ACCS[k]=r.accts[k].n; }); }
    if(r.auth&&r.auth.perms){ S.auth=r.auth; (r.auth.roles||[]).forEach(x=>{ ROLES[x.c]={n:x.n,d:x.d,dept:x.dept,ph:x.ph}; });
      ROLE_ORDER.length=0; (r.auth.roles||[]).forEach(x=>ROLE_ORDER.push(x.c)); S.sideKey=''; }
    let mdChanged=false;
    if(r.md) Object.keys(r.md).forEach(co=>{ const nv=r.md[co]; if(JSON.stringify(S.md[co])!==JSON.stringify(nv)){ S.md[co]=nv; S.ver[co]=(S.ver[co]||0)+1; mdChanged=true; } });
    const users={}; (r.users||[]).forEach(u=>users[u.id]=u);
    const meta=JSON.stringify([r.me,r.cfg,r.users]);
    let changed=mdChanged;
    if(meta!==S.metaKey){ S.metaKey=meta; S.users=users; S.cfg=Object.assign({tol:5,poAuto:0,credit:true},r.cfg||{}); S.sideKey=''; changed=true; }
    const ep=r.epochs||{}; let reset=false;
    COS.forEach(co=>{ if((S.epochs[co]||0)!==(ep[co]||0)){ reset=true; } });
    S.epochs=ep;
    if(full){ S.docs={}; COS.forEach(co=>S.ver[co]=(S.ver[co]||0)+1); changed=true; }
    (r.docs||[]).forEach(x=>{ const m=(S.docs[x.co]=S.docs[x.co]||{}); const old=m[x.id];
      if(!old||JSON.stringify(old)!==JSON.stringify(x.data)){ m[x.id]=x.data; S.ver[x.co]=(S.ver[x.co]||0)+1; changed=true; } });
    S.since=r.now;
    ctxResolve();
    if(!S.isAdmin && before && before!==JSON.stringify([S.me.co,S.me.role])){ S.docs={}; S.since=null; S.screen='HOME'; S.param=null; S.sideKey=''; syncing=null; await sync(true); render(true); return; }
    if(reset&&!full){ S.since=null; syncing=null; await sync(true); return; }
    if(changed) schedule();
  })();
  try{ await syncing; } finally { syncing=null; }
}
function startPolling(){
  clearTimeout(S.timer);
  const tick = async()=>{
    try{ await sync(); setOnline(true); }
    catch(e){ if(e.code==='28000'){ logout(); return; } setOnline(false); }
    S.timer=setTimeout(tick, document.hidden?30000:5000);
  };
  S.timer=setTimeout(tick,5000);
}
document.addEventListener('visibilitychange',()=>{ if(!document.hidden&&S.token){ sync().catch(()=>{}); } });
function setOnline(v){ if(S.online!==v){ S.online=v; renderCtx(); } }
function logout(){
  const t=S.token; clearTimeout(S.timer);
  if(t) api('erp_logout',{p_token:t}).catch(()=>{});
  LS.del('erp.token'); Object.assign(S,{token:null,me:null,uid:null,isAdmin:false,users:{},md:{},auth:null,docs:{},since:null,epochs:{},metaKey:'',screen:'HOME',param:null,stack:[],sideKey:''});
  showLogin();
}
let rt=null; function schedule(){ if(rt) return; rt=requestAnimationFrame(()=>{rt=null;render(false);}); }

/* ============ RENDER ============ */
const LIVE_FORM = {'ME51N':1,'VA01':1};
function isFormScreen(){
  if(S.me&&S.me.must_change) return true;
  if(LIVE_FORM[S.screen]) return true;
  if(['ME21N','MIGO','MIRO','F-53','VL01N','VF01','F-28'].includes(S.screen)&&S.param) return true;
  if(S.screen==='SPRO'||S.screen==='PW') return true;
  if(S.screen==='SU01'&&S.editExtra) return true;
  if(typeof MD_EDITING==='function'&&MD_EDITING()) return true;
  return false;
}
function render(force,keepScroll){
  ctxResolve();
  renderCtx(); renderSide();
  if(!force && isFormScreen()) return;
  const main = document.getElementById('main');
  const y = window.scrollY;
  let html;
  try{ html = screenHTML(); }catch(e){ console.error(e); html = `<div class="wrap"><div class="err"><b>Lỗi hiển thị:</b> ${esc(e.message)}</div></div>`; }
  main.innerHTML = html;
  if(!force||keepScroll) window.scrollTo(0,y);
  const f = main.querySelector('form[data-calc]'); if(f&&CALC[f.dataset.calc]) CALC[f.dataset.calc](f);
}
function renderCtx(){
  const el = document.getElementById('ctx');
  if(!S.me){ el.innerHTML=''; el.dataset.k=''; return; }
  let h='';
  if(S.isAdmin){
    h += `<select id="sel-co" data-chg="co" aria-label="Công ty">${COS.map(c=>`<option value="${c}" ${c===S.co?'selected':''}>${c} · Nhóm ${+c.slice(1)}</option>`).join('')}</select>`;
    h += `<select id="sel-role" data-chg="role" aria-label="Thao tác với vai trò">${['GV',...ROLE_ORDER].map(r=>`<option value="${r}" ${r===S.role?'selected':''}>${r==='GV'?'Giảng viên – toàn quyền':'Thao tác như: '+ROLES[r].n+(ROLES[r].ph&&ROLES[r].ph>'P2'?' (mở từ '+ROLES[r].ph+')':'')}</option>`).join('')}</select>`;
  } else if(S.co){
    const xr=myRoles().slice(1), xg=myGrants();
    h += `<span class="rolechip"><span class="dot" style="background:var(--r-${S.role})"></span>${esc(roleName(S.role))}${xr.length||xg.length?` <span style="font-weight:500;color:var(--shell-mute)">+ kiêm ${xr.length+xg.length}</span>`:''}</span><span class="who">${esc(S.co)} · ${esc(coName(S.co))}</span>`;
  }
  if(CFG.env==='dev') h = `<span class="rolechip" style="background:var(--warn);color:#fff" title="Dữ liệu ở project erp-lab-dev, không phải lớp học">Môi trường thử</span>` + h;
  h += `<span class="who"><b>${esc(S.me.full_name)}</b> <span class="mono">${esc(S.me.username)}</span></span>`;
  if(!S.online) h += `<span class="rolechip" style="background:var(--bad)">Mất kết nối</span>`;
  h += `<button class="btn sm" data-go="PW" style="background:var(--shell-2);color:var(--shell-fg);border-color:transparent">Đổi mật khẩu</button><button class="btn sm" data-act="logout" style="background:var(--shell-2);color:var(--shell-fg);border-color:transparent">Đăng xuất</button>`;
  if(el.dataset.k!==h){ el.innerHTML=h; el.dataset.k=h; }
}
function renderSide(){
  const side = document.getElementById('side');
  if(!S.me){ side.innerHTML=''; S.sideKey=''; return; }
  if(!S.co && !S.isAdmin){ if(S.sideKey!=='none'){ side.innerHTML='<h4>Chưa được phân quyền</h4><p class="small muted" style="padding:0 16px">Menu giao dịch sẽ hiện sau khi giảng viên gán bạn vào công ty và vai trò.</p>'; S.sideKey='none'; } return; }
  const c = calc(S.co);
  const cnt = {'ME21N':c.Q.prForPO.length,'MIGO':c.Q.poForGR.length,'MIRO':c.Q.poForIV.length,'F-53':c.Q.ivForPay.length,'VL01N':c.Q.soForDL.length,'VF01':c.Q.dlForBI.length,'F-28':c.Q.biForRC.length,
    'SBWP':c.Q.apAll.length,'ZMDA':typeof mdPendingCount==='function'?mdPendingCount(S.co):0,'ME54N':c.Q.ap.PR.length,'ME29N':c.Q.ap.PO.length,'MRBR':c.Q.ap.IV.length,'VKM3':c.Q.ap.SO.length,'ZFAP':c.Q.ap.PAY.length+c.Q.ap.RC.length};
  const groups = {};
  Object.keys(TC).forEach(k=>{ const t=TC[k]; if(t.admin&&!S.isAdmin) return; (groups[t.m]=groups[t.m]||[]).push(k); });
  let h = `<button class="mi ${S.screen==='HOME'?'on':''}" data-go="HOME"><code>HOME</code><span>Trang làm việc</span><span></span></button>`;
  const GORD=['Mua hàng (MM)','Bán hàng (SD)','Kế toán (FI)','Dữ liệu gốc','Phê duyệt','Kiểm soát','Hướng dẫn','Quản trị (giảng viên)'];
  Object.keys(groups).sort((a,b)=>{const i=x=>{const k=GORD.indexOf(x);return k<0?99:k;};return i(a)-i(b);}).forEach(g=>{
    h += `<h4>${esc(g)}</h4>`;
    groups[g].forEach(k=>{ const ok=allowed(k); const n=ok?cnt[k]:0;
      h += `<button class="mi ${S.screen===k?'on':''} ${ok?'':'locked'}" data-go="${k}" title="${ok?'':'Không có quyền – vai trò được phép: '+esc(rolesFor(k))}"><code>${k}</code><span>${esc(TC[k].t)}</span>${n?`<span class="badge">${n}</span>`:(ok?'<span></span>':'<span class="lk">khóa</span>')}</button>`; });
  });
  h += `<p class="small muted" style="padding:12px 16px 20px;margin:0">ERP Lab – mô phỏng giáo dục độc lập, không liên kết với SAP SE. Hệ thống tài khoản theo TT 99/2025/TT-BTC.</p>`;
  const key = h;
  if(S.sideKey!==key){ side.innerHTML=h; S.sideKey=key; }
}
function go(tc,param){
  tc = String(tc||'').toUpperCase().trim();
  if(tc!=='HOME'&&tc!=='DOC'&&tc!=='PW'&&!TC[tc]){ toast('Mã giao dịch '+tc+' không tồn tại.'); return; }
  S.stack.push({s:S.screen,p:S.param});
  S.screen=tc; S.param=param||null;
  document.getElementById('side').classList.remove('open');
  render(true); window.scrollTo(0,0);
}
function back(){ const b=S.stack.pop(); if(b){S.screen=b.s;S.param=b.p;} else {S.screen='HOME';S.param=null;} render(true); window.scrollTo(0,0); }

function head(tc,title,desc,acts){
  return `<div class="ph"><div><div class="tc">${esc(tc)}</div><h1>${esc(title)}</h1>${desc?`<p>${desc}</p>`:''}</div><div class="acts">${acts||''}<button class="btn sm" data-act="back">← Quay lại</button></div></div>`;
}

function screenHTML(){
  if(S.me&&S.me.must_change) return scrPW(true);
  if(S.screen==='PW') return scrPW(false);
  if(!S.isAdmin && !S.co){ return scrWaiting(); }
  const s = S.screen;
  if(s==='HOME') return scrHome();
  if(s==='DOC') return scrDoc();
  if(TC[s] && !allowed(s)) return scrNoAuth(s);
  const F = {'ME51N':scrPR,'ME21N':scrPO,'MIGO':scrGR,'MIRO':scrIV,'F-53':scrPAY,'VA01':scrSO,'VL01N':scrDL,'VF01':scrBI,'F-28':scrRC,
    'MMBE':scrStock,'FBL1N':scrAP,'FBL5N':scrAR,'ZNKC':scrNKC,'F.01':scrTB,'ZCASE':scrCase,'PFCG':scrPFCG,'SU01':scrUsers,'ZOVR':scrOverview,'SPRO':scrConfig};
  if(F[s]) return F[s]();
  if(SCREENS[s]) return SCREENS[s]();
  if(TC[s]&&TC[s].list) return scrList(s);
  if(TC[s]&&'ap' in TC[s]) return scrInbox(s);
  return scrHome();
}

/* ============ SCREENS: ACCESS ============ */
function scrNoAuth(tc){
  return `<div class="wrap">${head('SU53','Không đủ quyền thực hiện giao dịch','')}
  <div class="panel"><p style="margin-top:0">Vai trò hiện tại <b>${esc(roleName(S.role))}</b> không được cấp quyền giao dịch <code>${esc(tc)}</code> – ${esc(TC[tc].t)}.</p>
  <dl class="kv"><dt>Vai trò được phép</dt><dd>${esc(rolesFor(tc))}</dd><dt>Quyền của bạn</dt><dd>${esc(S.isAdmin?roleName(S.role):rolesLabel(S.me))}</dd><dt>Nguyên tắc kiểm soát</dt><dd>Bất kiêm nhiệm: người lập, người phê duyệt, người giữ tài sản và người ghi sổ phải là những người khác nhau. Nhóm thiếu người thì giảng viên có thể giao kiêm nhiệm trong SU01.</dd></dl>
  <p class="small muted">Xem toàn bộ ma trận ở giao dịch <button class="linkbtn" data-go="PFCG">PFCG</button>.</p></div></div>`;
}
function scrWaiting(){
  return `<div class="wrap" style="max-width:640px"><div class="ph"><div><div class="tc">SU01</div><h1>Chờ giảng viên phân công</h1>
  <p>Tài khoản <b class="mono">${esc(S.me.username)}</b> – ${esc(S.me.full_name)} đã đăng nhập. Khi giảng viên gán bạn vào một công ty và vai trò, menu giao dịch sẽ tự mở (trang tự cập nhật sau vài giây).</p></div></div>
  <div class="panel"><h2>Trong lúc chờ</h2><p class="small" style="margin:0">Đọc tình huống thực hành ở <button class="linkbtn" data-act="peekCase">ZCASE</button> và ma trận phân quyền ở <button class="linkbtn" data-act="peekPfcg">PFCG</button>.</p></div>
  ${S.peek?S.peek():''}</div>`;
}
function scrPW(forced){
  return `<div class="wrap" style="max-width:520px"><div class="ph"><div><div class="tc">SU3 · Mật khẩu</div><h1>${forced?'Đặt mật khẩu mới':'Đổi mật khẩu'}</h1>
  <p>${forced?'Đây là lần đầu bạn đăng nhập bằng mật khẩu do giảng viên cấp. Hãy đặt mật khẩu riêng (ít nhất 6 ký tự) trước khi làm việc.':'Mật khẩu cần ít nhất 6 ký tự.'}</p></div>${forced?'':'<div class="acts"><button class="btn sm" data-act="back">← Quay lại</button></div>'}</div>
  <form class="form panel" data-form="PW"><div class="err"></div>
   <label class="field"><span>Mật khẩu hiện tại</span><input id="p-old" type="password" autocomplete="current-password" required></label>
   <label class="field"><span>Mật khẩu mới</span><input id="p-new" type="password" autocomplete="new-password" minlength="6" required></label>
   <label class="field"><span>Nhập lại mật khẩu mới</span><input id="p-new2" type="password" autocomplete="new-password" minlength="6" required></label>
   <div class="form-foot"><span></span><button class="btn pri">Lưu mật khẩu</button></div></form></div>`;
}
function showLogin(msg){
  document.getElementById('side').innerHTML=''; renderCtx();
  document.getElementById('main').innerHTML = `<div class="wrap" style="max-width:440px;margin:40px auto 0">
  <div class="ph"><div><div class="tc">Đăng nhập hệ thống</div><h1>ERP Lab HTTTKT</h1><p>Thực hành chu trình Mua hàng – Thanh toán và Bán hàng – Thu tiền. Dùng MSSV và mật khẩu giảng viên cấp.</p></div></div>
  <form class="form panel" data-form="LOGIN" autocomplete="on"><div class="err">${msg?esc(msg):''}</div>
   <label class="field"><span>Tên đăng nhập (sinh viên: MSSV · giảng viên: gv)</span><input id="l-user" autocomplete="username" autocapitalize="none" spellcheck="false" required autofocus></label>
   <label class="field"><span>Mật khẩu</span><input id="l-pass" type="password" autocomplete="current-password" autocapitalize="none" required></label>
   <div class="form-foot"><span class="small muted">Quên mật khẩu? Nhờ giảng viên cấp lại.</span><button class="btn pri">Đăng nhập</button></div></form></div>`;
}
function showSetup(){
  document.getElementById('main').innerHTML = `<div class="wrap" style="max-width:720px;margin-top:20px"><div class="ph"><div><div class="tc">Cài đặt</div><h1>Chưa cấu hình cơ sở dữ liệu</h1>
  <p>Trang cần địa chỉ Supabase để lưu dữ liệu chung của lớp. Giảng viên mở file <code>erp/config.js</code> trong kho GitHub và điền <code>supabaseUrl</code>, <code>supabaseAnonKey</code> theo hướng dẫn trong <code>erp/README.md</code>.</p></div></div></div>`;
}
