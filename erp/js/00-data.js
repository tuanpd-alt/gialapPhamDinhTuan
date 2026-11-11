"use strict";
/* ERP Lab – Dữ liệu gốc dự phòng, loại chứng từ, danh mục T-code. Từ P2 dữ liệu gốc đọc từ máy chủ. */
/* ============ MASTER DATA (giống nhau cho cả 8 công ty) ============ */
// Thuế suất GTGT lấy từ tham số máy chủ (SPRO); 0.10 chỉ là giá trị dự phòng khi chưa đồng bộ.
function VATR(){ return (typeof S!=='undefined'&&S.cfg&&S.cfg.vat!=null)?+S.cfg.vat:0.10; }
const YY = String(new Date().getFullYear()).slice(2);
const COS = ['C01','C02','C03','C04','C05','C06','C07','C08'];
const coName = c => 'Công ty CP Thương mại Cánh Buồm ' + c.slice(1);
const MATS0 = [
  {c:'HH01',n:'Laptop văn phòng 14 inch',u:'Cái',oq:20,oc:18500000,bp:18500000,sp:23900000},
  {c:'HH02',n:'Màn hình 24 inch IPS',u:'Cái',oq:40,oc:2600000,bp:2600000,sp:3450000},
  {c:'HH03',n:'Máy in laser A4',u:'Cái',oq:15,oc:3900000,bp:3900000,sp:4990000},
  {c:'HH04',n:'Chuột không dây',u:'Cái',oq:100,oc:290000,bp:290000,sp:420000},
  {c:'HH05',n:'Bàn phím cơ',u:'Cái',oq:50,oc:950000,bp:950000,sp:1290000}
];
const VENDORS0 = [
  {c:'NCC01',n:'Công ty TNHH Phân phối Tin học Sao Mai',mst:'4201234567',f:1.00,terms:30},
  {c:'NCC02',n:'Công ty CP Thiết bị Văn phòng Hải Âu',mst:'0312345678',f:0.97,terms:15},
  {c:'NCC03',n:'Công ty TNHH Linh kiện Bến Thành',mst:'0309876543',f:1.03,terms:45}
];
const CUSTS0 = [
  {c:'KH01',n:'Công ty TNHH Du lịch Biển Xanh',mst:'4201112223',lim:300000000,terms:30},
  {c:'KH02',n:'Công ty CP Thủy sản Hòn Tre',mst:'4203334445',lim:500000000,terms:30},
  {c:'KH03',n:'Cửa hàng Tin học Phước Hải',mst:'4205556667',lim:150000000,terms:15}
];
const ACCS = { // danh mục dự phòng; erp_sync trả về đầy đủ hệ thống tài khoản (Phụ lục II TT 99/2025/TT-BTC)
  '111':'Tiền mặt','112':'Tiền gửi không kỳ hạn','131':'Phải thu của khách hàng',
  '1331':'Thuế GTGT được khấu trừ của hàng hóa, dịch vụ','156':'Hàng hóa','331':'Phải trả cho người bán',
  '33311':'Thuế GTGT đầu ra','4111':'Vốn góp của chủ sở hữu','511':'Doanh thu bán hàng và cung cấp dịch vụ','632':'Giá vốn hàng bán'
};
MATS0.forEach(m=>Object.assign(m,{t:'HH',acc:'156',active:true,min:0,from:'2026-01-01'}));
VENDORS0.forEach(m=>Object.assign(m,{k:'V',active:true,ok:true})); CUSTS0.forEach(m=>Object.assign(m,{k:'C',active:true,ok:true,f:1}));
const INV0 = MATS0.reduce((s,m)=>s+m.oq*m.oc,0);
// Số dư đầu kỳ do máy chủ ghi thành chứng từ mở sổ (loại OB); không còn hằng số ở trình duyệt.
/* Từ P2: dữ liệu gốc riêng từng công ty, đọc từ erp_sync (md). MATS/VENDORS/CUSTS trả về danh mục của công ty đang làm việc;
   MATS0/VENDORS0/CUSTS0 chỉ là dự phòng khi chưa đồng bộ. */
function mdOf(co){ return (typeof S!=='undefined'&&S.md&&co&&S.md[co])||null; }
function matsOf(co){ const m=mdOf(co); return m?m.mats:MATS0; }
function vensOf(co){ const m=mdOf(co); return m?m.partners.filter(p=>p.k==='V'):VENDORS0; }
function custsOf(co){ const m=mdOf(co); return m?m.partners.filter(p=>p.k==='C'):CUSTS0; }
const curCo = () => (typeof S!=='undefined'&&S.co)||null;
Object.defineProperty(globalThis,'MATS',{get(){ return matsOf(curCo()); }});
Object.defineProperty(globalThis,'VENDORS',{get(){ return vensOf(curCo()); }});
Object.defineProperty(globalThis,'CUSTS',{get(){ return custsOf(curCo()); }});
const MAT_NONE = {c:'?',n:'(không có trong danh mục)',u:'',t:'HH',acc:'156',oq:0,oc:0,bp:0,sp:0,active:false};
const mat = (c,co) => matsOf(co||curCo()).find(m=>m.c===c) || MATS0.find(m=>m.c===c) || Object.assign({},MAT_NONE,{c});
const ven = (c,co) => vensOf(co||curCo()).find(v=>v.c===c);
const cus = (c,co) => custsOf(co||curCo()).find(v=>v.c===c);
const MTYPE = {HH:'Hàng hóa (TK 156)',NVL:'Nguyên vật liệu, linh kiện (TK 152)',TP:'Thành phẩm (TK 155)',DV:'Dịch vụ (không tồn kho)'};
const INV_ACCS = ['152','155','156'];
const isStock = m => m && m.t!=='DV';
const todayISO = () => (typeof today==='function'?today():new Date().toISOString().slice(0,10));
const effective = m => m.active!==false && String(m.from||'').slice(0,10)<=todayISO();
// Danh mục dùng để chọn trên chứng từ: chỉ bản ghi đang hoạt động, đã hiệu lực, đối tượng đã được xác nhận.
const buyMats  = co => matsOf(co).filter(m=>effective(m)&&(m.t==='HH'||m.t==='NVL'));
const sellMats = co => matsOf(co).filter(m=>effective(m)&&(m.t==='HH'||m.t==='TP'));
const okVens   = co => vensOf(co).filter(v=>v.active!==false&&v.ok!==false);
const okCusts  = co => custsOf(co).filter(v=>v.active!==false&&v.ok!==false);
// Đơn giá mua đề xuất: bảng giá ME11 hiệu lực gần nhất; không có thì giá tham khảo × hệ số nhà cung cấp.
function priceOf(co,v,m,date){
  const d=String(date||todayISO()); const md=mdOf(co);
  const hit=md?(md.prices||[]).filter(x=>x.v===v&&x.m===m&&String(x.from)<=d).sort((a,b)=>String(b.from).localeCompare(String(a.from)))[0]:null;
  if(hit) return {p:+hit.p,src:'ME11 từ '+String(hit.from).slice(0,10)};
  const vv=ven(v,co); return {p:Math.round(mat(m,co).bp*((vv&&vv.f)||1)),src:'giá tham khảo'};
}

// Danh mục vai trò dự phòng; erp_sync (auth.roles) ghi đè bằng bảng erp_role trên máy chủ (SPEC mục 4).
const ROLES = {
  GD:{n:'Giám đốc',d:'Xem báo cáo; duyệt cấp 2 (từ P4)'},
  MH:{n:'Nhân viên mua hàng',d:'Đơn mua, dữ liệu gốc nhà cung cấp và vật tư, bảng giá mua'},
  KHO:{n:'Thủ kho',d:'Lập đề nghị mua, nhập kho theo đơn mua, xuất kho giao hàng'},
  KD:{n:'Nhân viên kinh doanh',d:'Đơn bán, dữ liệu gốc khách hàng'},
  SX:{n:'Kế hoạch – Quản đốc',d:'BOM, MRP, lệnh sản xuất (P7)'},
  NS:{n:'Nhân sự – tiền lương',d:'Hồ sơ, chấm công, tính lương (P9)'},
  KT:{n:'Kế toán công nợ (phải trả + phải thu)',d:'Gộp AP và AR'},
  AP:{n:'Kế toán phải trả',d:'Hóa đơn mua, đề nghị chi'},
  AR:{n:'Kế toán phải thu',d:'Hóa đơn bán, thu tiền'},
  GT:{n:'Kế toán kho – giá thành',d:'Giá thành, chênh lệch (P7–P8)'},
  TS:{n:'Kế toán tài sản cố định',d:'TSCĐ, khấu hao (P6)'},
  TH:{n:'Kế toán tổng hợp',d:'Bút toán tổng hợp, kết chuyển (P3)'},
  TQ:{n:'Thủ quỹ',d:'Thu chi tiền mặt (P3)'},
  KTT:{n:'Kế toán trưởng',d:'Phê duyệt chứng từ tài chính, gỡ khóa, duyệt thay đổi dữ liệu gốc nhạy cảm'},
  KSNB:{n:'Kiểm toán nội bộ',d:'Chỉ đọc: sổ sách, nhật ký thay đổi'}
};
const ROLE_ORDER = Object.keys(ROLES);
// Các phần việc tối thiểu để hai chu trình P2P, O2C chạy được (dùng cho sơ đồ tổ chức và cảnh báo phân công).
const DUTIES = [{c:'KHO',n:'Thủ kho',g:['PR','GR','DL']},{c:'MH',n:'Mua hàng',g:['PO']},{c:'KD',n:'Kinh doanh',g:['SO']},
  {c:'AP',n:'Kế toán phải trả',g:['IV','PAY']},{c:'AR',n:'Kế toán phải thu',g:['BI','RC']},{c:'KTT',n:'Kế toán trưởng (phê duyệt)',g:['AP']}];
// Cột của ma trận PFCG: vai trò đã có quyền ở giai đoạn hiện tại.
const PFCG_COLS = ['GD','MH','KHO','KD','AP','AR','KTT','KSNB'];
const roleName = r => r==='GV' ? 'Giảng viên (toàn quyền)' : (ROLES[r]?ROLES[r].n:'—');

const TYPES = {
  PR:{n:'Đề nghị mua hàng',pre:'100000',tc:'ME51N'},
  PO:{n:'Đơn mua hàng',pre:'450000',tc:'ME21N'},
  GR:{n:'Phiếu nhập kho',pre:'500000',tc:'MIGO'},
  IV:{n:'Hóa đơn mua vào',pre:'510000',tc:'MIRO'},
  PAY:{n:'Phiếu chi / Ủy nhiệm chi',pre:'150000',tc:'F-53'},
  SO:{n:'Đơn bán hàng',pre:'000010',tc:'VA01'},
  DL:{n:'Phiếu xuất kho',pre:'800000',tc:'VL01N'},
  BI:{n:'Hóa đơn GTGT bán ra',pre:'900000',tc:'VF01'},
  RC:{n:'Phiếu thu / Giấy báo Có',pre:'140000',tc:'F-28'},
  OB:{n:'Chứng từ mở sổ (số dư đầu kỳ)',pre:'000000',tc:'ZNKC'}
};
const ALL = 'ALL';
const TC = {
  'ME51N':{m:'Mua hàng (MM)',t:'Tạo đề nghị mua hàng',r:['KHO']},
  'ME5A': {m:'Mua hàng (MM)',t:'Danh sách đề nghị mua',r:ALL,list:['PR']},
  'ME21N':{m:'Mua hàng (MM)',t:'Tạo đơn mua hàng',r:['MH']},
  'ME2N': {m:'Mua hàng (MM)',t:'Danh sách đơn mua hàng',r:ALL,list:['PO']},
  'MIGO': {m:'Mua hàng (MM)',t:'Nhập kho theo đơn mua',r:['KHO']},
  'MB51': {m:'Mua hàng (MM)',t:'Nhật ký nhập – xuất kho',r:ALL,list:['GR','DL']},
  'MMBE': {m:'Mua hàng (MM)',t:'Tồn kho & thẻ kho (152, 155, 156)',r:ALL},
  'VA01': {m:'Bán hàng (SD)',t:'Tạo đơn bán hàng',r:['KD']},
  'VA05': {m:'Bán hàng (SD)',t:'Danh sách đơn bán hàng',r:ALL,list:['SO']},
  'VL01N':{m:'Bán hàng (SD)',t:'Giao hàng & xuất kho',r:['KHO']},
  'VF01': {m:'Bán hàng (SD)',t:'Lập hóa đơn bán hàng',r:['AR']},
  'VF05': {m:'Bán hàng (SD)',t:'Danh sách hóa đơn bán',r:ALL,list:['BI','RC']},
  'MIRO': {m:'Kế toán (FI)',t:'Nhận & đối chiếu hóa đơn mua',r:['AP']},
  'MIR5': {m:'Kế toán (FI)',t:'Danh sách hóa đơn mua & phiếu chi',r:ALL,list:['IV','PAY']},
  'F-53': {m:'Kế toán (FI)',t:'Đề nghị thanh toán nhà cung cấp',r:['AP']},
  'F-28': {m:'Kế toán (FI)',t:'Ghi nhận thu tiền khách hàng',r:['AR']},
  'FBL1N':{m:'Kế toán (FI)',t:'Công nợ phải trả (TK 331)',r:['MH','KT','KTT']},
  'FBL5N':{m:'Kế toán (FI)',t:'Công nợ phải thu (TK 131)',r:['KD','KT','KTT']},
  'ZNKC': {m:'Kế toán (FI)',t:'Sổ Nhật ký chung',r:['KT','KTT']},
  'F.01': {m:'Kế toán (FI)',t:'Bảng cân đối số phát sinh',r:['KT','KTT']},
  'SBWP': {m:'Phê duyệt',t:'Hộp phê duyệt (tất cả)',r:['KTT'],ap:null},
  'ME54N':{m:'Phê duyệt',t:'Duyệt đề nghị mua',r:['KTT'],ap:['PR']},
  'ME29N':{m:'Phê duyệt',t:'Duyệt đơn mua hàng',r:['KTT'],ap:['PO']},
  'MRBR': {m:'Phê duyệt',t:'Gỡ khóa hóa đơn mua',r:['KTT'],ap:['IV']},
  'VKM3': {m:'Phê duyệt',t:'Gỡ khóa tín dụng đơn bán',r:['KTT'],ap:['SO']},
  'ZFAP': {m:'Phê duyệt',t:'Duyệt phiếu chi & phiếu thu',r:['KTT'],ap:['PAY','RC']},
  'ZCASE':{m:'Hướng dẫn',t:'Tình huống thực hành',r:ALL},
  'PFCG': {m:'Hướng dẫn',t:'Ma trận phân quyền',r:ALL},
  'SU01': {m:'Quản trị (giảng viên)',t:'Sinh viên & phân quyền',admin:true},
  'ZOVR': {m:'Quản trị (giảng viên)',t:'Tổng quan 8 nhóm',admin:true},
  'SPRO': {m:'Quản trị (giảng viên)',t:'Tham số & dữ liệu',admin:true}
};

