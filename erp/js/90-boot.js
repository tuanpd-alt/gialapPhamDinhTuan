"use strict";
/* ERP Lab – Khởi động. */
/* ============ BOOT ============ */
function parseRoster(t){
  return String(t||'').split(/\r?\n/).map(l=>l.split(/\t|;|,/).map(x=>x.trim())).filter(c=>c[0]&&c[1]&&/^[A-Za-z0-9._-]{3,30}$/.test(c[0]))
    .map(c=>({mssv:c[0],name:c[1],grp:/^[1-8]$/.test(c[2]||'')?c[2]:''}));
}
async function start(){
  document.getElementById('main').innerHTML='<div class="boot">Đang tải dữ liệu…</div>';
  try{ await sync(true); }
  catch(e){ if(e.code==='28000'){ logout(); return; } showLogin(dbErr(e)); return; }
  { const h=decodeURIComponent((location.hash||'').slice(1)).toUpperCase(); S.screen=(TC[h]&&!TC[h].admin)?h:'HOME'; } S.param=null; S.stack=[];
  render(true); startPolling();
}
(function boot(){
  if(!CFG.supabaseUrl||!CFG.supabaseAnonKey||/YOUR|DIEN_/.test(CFG.supabaseUrl+CFG.supabaseAnonKey)){ showSetup(); return; }
  S.token=LS.get('erp.token');
  if(S.token) start(); else showLogin();
})();
