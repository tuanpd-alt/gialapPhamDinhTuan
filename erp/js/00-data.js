"use strict";
/* ERP Lab – Dữ liệu gốc dự phòng, loại chứng từ, danh mục T-code. Từ P2 dữ liệu gốc đọc từ máy chủ. */
/* ============ MASTER DATA (giống nhau cho cả 8 công ty) ============ */
// Thuế suất GTGT lấy từ tham số máy chủ (SPRO); 0.10 chỉ là giá trị dự phòng khi chưa đồng bộ.
function VATR(){ return (typeof S!=='undefined'&&S.cfg&&S.cfg.vat!=null)?+S.cfg.vat:0.10; }
const YY = String(new Date().getFullYear()).slice(2);
const COS = ['C01','C02','C03','C04','C05','C06','C07','C08'];
const coName = c => 'Công ty CP Thương mại Cánh Buồm ' + c.slice(1);
const MATS = [
  {c:'HH01',n:'Laptop văn phòng 14 inch',u:'Cái',oq:20,oc:18500000,bp:18500000,sp:23900000},
  {c:'HH02',n:'Màn hình 24 inch IPS',u:'Cái',oq:40,oc:2600000,bp:2600000,sp:3450000},
  {c:'HH03',n:'Máy in laser A4',u:'Cái',oq:15,oc:3900000,bp:3900000,sp:4990000},
  {c:'HH04',n:'Chuột không dây',u:'Cái',oq:100,oc:290000,bp:290000,sp:420000},
  {c:'HH05',n:'Bàn phím cơ',u:'Cái',oq:50,oc:950000,bp:950000,sp:1290000}
];
const VENDORS = [
  {c:'NCC01',n:'Công ty TNHH Phân phối Tin học Sao Mai',mst:'4201234567',f:1.00,terms:30},
  {c:'NCC02',n:'Công ty CP Thiết bị Văn phòng Hải Âu',mst:'0312345678',f:0.97,terms:15},
  {c:'NCC03',n:'Công ty TNHH Linh kiện Bến Thành',mst:'0309876543',f:1.03,terms:45}
];
const CUSTS = [
  {c:'KH01',n:'Công ty TNHH Du lịch Biển Xanh',mst:'4201112223',lim:300000000,terms:30},
  {c:'KH02',n:'Công ty CP Thủy sản Hòn Tre',mst:'4203334445',lim:500000000,terms:30},
  {c:'KH03',n:'Cửa hàng Tin học Phước Hải',mst:'4205556667',lim:150000000,terms:15}
];
const ACCS = { // danh mục dự phòng; erp_sync trả về đầy đủ hệ thống tài khoản (Phụ lục II TT 99/2025/TT-BTC)
  '111':'Tiền mặt','112':'Tiền gửi không kỳ hạn','131':'Phải thu của khách hàng',
  '1331':'Thuế GTGT được khấu trừ của hàng hóa, dịch vụ','156':'Hàng hóa','331':'Phải trả cho người bán',
  '33311':'Thuế GTGT đầu ra','4111':'Vốn góp của chủ sở hữu','511':'Doanh thu bán hàng và cung cấp dịch vụ','632':'Giá vốn hàng bán'
};
const INV0 = MATS.reduce((s,m)=>s+m.oq*m.oc,0);
// Số dư đầu kỳ do máy chủ ghi thành chứng từ mở sổ (loại OB); không còn hằng số ở trình duyệt.
const mat = c => MATS.find(m=>m.c===c);
const ven = c => VENDORS.find(v=>v.c===c);
const cus = c => CUSTS.find(v=>v.c===c);

const ROLES = {
  KHO:{n:'Thủ kho',d:'Lập đề nghị mua, nhập kho theo đơn mua, xuất kho giao hàng'},
  MH:{n:'Nhân viên mua hàng',d:'Chọn nhà cung cấp, lập đơn mua hàng'},
  KD:{n:'Nhân viên kinh doanh',d:'Nhận và lập đơn bán hàng'},
  KT:{n:'Kế toán công nợ',d:'Kiểm tra hóa đơn mua, đề nghị chi, lập hóa đơn bán, ghi nhận thu tiền'},
  KTT:{n:'Kế toán trưởng',d:'Phê duyệt đề nghị mua, đơn mua, tín dụng, hóa đơn bị khóa, phiếu chi/thu'}
};
const ROLE_ORDER = ['KHO','MH','KD','KT','KTT'];
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
  'MMBE': {m:'Mua hàng (MM)',t:'Tồn kho & thẻ kho',r:ALL},
  'VA01': {m:'Bán hàng (SD)',t:'Tạo đơn bán hàng',r:['KD']},
  'VA05': {m:'Bán hàng (SD)',t:'Danh sách đơn bán hàng',r:ALL,list:['SO']},
  'VL01N':{m:'Bán hàng (SD)',t:'Giao hàng & xuất kho',r:['KHO']},
  'VF01': {m:'Bán hàng (SD)',t:'Lập hóa đơn bán hàng',r:['KT']},
  'VF05': {m:'Bán hàng (SD)',t:'Danh sách hóa đơn bán',r:ALL,list:['BI','RC']},
  'MIRO': {m:'Kế toán (FI)',t:'Nhận & đối chiếu hóa đơn mua',r:['KT']},
  'MIR5': {m:'Kế toán (FI)',t:'Danh sách hóa đơn mua & phiếu chi',r:ALL,list:['IV','PAY']},
  'F-53': {m:'Kế toán (FI)',t:'Đề nghị thanh toán nhà cung cấp',r:['KT']},
  'F-28': {m:'Kế toán (FI)',t:'Ghi nhận thu tiền khách hàng',r:['KT']},
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

