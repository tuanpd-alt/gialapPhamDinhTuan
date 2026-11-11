-- =====================================================================
-- Kiểm thử P3 – sổ cái, kỳ kế toán, tiền và ngân hàng. CHỈ CHẠY TRÊN erp-lab-dev (xóa dữ liệu C08).
-- Ba kịch bản nghiệm thu (lộ trình 4.5):
--   (1) đóng kỳ 11, ghi vào kỳ 11 bị chặn, đảo chứng từ kỳ 11 sang kỳ 12;
--   (2) đối chiếu ngân hàng ra đúng 3 khoản chênh lệch cài sẵn;
--   (3) FB50 ghi vào tài khoản phải thu bị chặn.
-- Thêm: trích trước tự đảo (FBS1), quỹ tiền mặt (FBCJ), kiểm quỹ, tạm ứng – quyết toán.
-- =====================================================================
drop table if exists tst_p3;
create table tst_p3(n serial, name text, ok boolean, detail text);
alter table tst_p3 enable row level security;
create or replace function t_ok(p_name text, p_ok boolean, p_detail text default '') returns void language sql as
$$ insert into tst_p3(name, ok, detail) values (p_name, coalesce(p_ok,false), coalesce(p_detail,'')) $$;
create or replace function t_eq(p_name text, p_got numeric, p_exp numeric) returns void language sql as
$$ select t_ok(p_name, p_got = p_exp, 'được ' || coalesce(p_got::text,'null') || ', kỳ vọng ' || p_exp) $$;

do $$
declare
  cfg0 jsonb; wd0 date; gv text; th text; tq text; ktt text; ap text; kho text; mh text; kd text;
  r jsonb; je1 text; je2 text; rev text; acr text; cj text; cnt text; adv text; ads text; pr text; po text; iv text; pay text;
  bk numeric; stmt numeric; unm numeric; nunm int; ln text;
begin
  select v into cfg0 from erp_cfg where k = 'main';
  update erp_cfg set v = v || '{"tol":5,"poAuto":0,"credit":true,"selfApprove":false,"vat":0.08,"bankClear":true}' where k = 'main';
  select wdate into wd0 from erp_co_state where co = 'C08';
  perform erp_purge_co('C08');
  delete from erp_user where username like 'tst\_%';
  insert into erp_user(username, full_name, pass_hash, co, role, must_change) values
    ('tst_th','Kế toán tổng hợp thử','x','C08','TH',false), ('tst_tq','Thủ quỹ thử','x','C08','TQ',false),
    ('tst_ktt','KTT thử','x','C08','KTT',false), ('tst_ap','Kế toán phải trả thử','x','C08','AP',false),
    ('tst_kho','Thủ kho thử','x','C08','KHO',false), ('tst_mh','Mua hàng thử','x','C08','MH',false),
    ('tst_kd','Kinh doanh thử','x','C08','KD',false);
  insert into erp_session(user_id, expires_at) select id, now() + interval '1 hour' from erp_user where username like 'tst\_%' or username = 'gv';
  select s.token::text into gv  from erp_session s join erp_user u on u.id=s.user_id where u.username='gv' order by s.expires_at desc limit 1;
  select s.token::text into th  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_th';
  select s.token::text into tq  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_tq';
  select s.token::text into ktt from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_ktt';
  select s.token::text into ap  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_ap';
  select s.token::text into kho from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_kho';
  select s.token::text into mh  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_mh';
  select s.token::text into kd  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_kd';
  -- Giảng viên đặt ngày làm việc 10/11/2026 và cài lại 3 khoản sao kê cài sẵn của tháng 11
  perform erp_admin_set_state(gv, 'C08', '{"wdate":"2026-11-10","reseed":true,"cashCount":""}');
  perform t_ok('SPRO: ngày làm việc C08 = 10/11/2026', erp_wdate('C08') = '2026-11-10');
  perform t_ok('Sao kê cài sẵn tháng 11: 3 khoản (tiền về chưa rõ, phí, lãi), chưa phát hành',
    (select count(*) = 3 and bool_and(not issued) from erp_bank_preset where co='C08' and vdate between '2026-11-01' and '2026-11-30'));

  -- ===== (3) FB50 chặn tài khoản đối chiếu, kiểm tra TTCP và cân Nợ – Có =====
  begin
    perform erp_doc_create(th,'C08','JE','{"date":"2026-11-10","memo":"Điều chỉnh công nợ","lines":[{"a":"131","dr":1000000},{"a":"511","cr":1000000}]}','','');
    perform t_ok('(3) FB50 ghi vào TK 131 phải thu bị chặn', false);
  exception when others then perform t_ok('(3) FB50 ghi vào TK 131 phải thu bị chặn', sqlerrm like 'TK 131 là tài khoản đối chiếu%', sqlerrm); end;
  begin
    perform erp_doc_create(th,'C08','JE','{"date":"2026-11-10","memo":"x","lines":[{"a":"156","dr":1000000},{"a":"3388","cr":1000000}]}','','');
    perform t_ok('FB50 ghi vào TK 156 tồn kho bị chặn', false);
  exception when others then perform t_ok('FB50 ghi vào TK 156 tồn kho bị chặn', sqlerrm like 'TK 156 là tài khoản đối chiếu%', sqlerrm); end;
  begin
    perform erp_doc_create(th,'C08','JE','{"date":"2026-11-10","memo":"x","lines":[{"a":"632","dr":1000000},{"a":"3388","cr":1000000}]}','','');
    perform t_ok('FB50 ghi vào TK 632 (không cho ghi tay) bị chặn', false);
  exception when others then perform t_ok('FB50 ghi vào TK 632 (không cho ghi tay) bị chặn', sqlerrm like '%không cho phép hạch toán tay%', sqlerrm); end;
  begin
    perform erp_doc_create(th,'C08','JE','{"date":"2026-11-10","memo":"x","lines":[{"a":"6427","dr":1000000},{"a":"3388","cr":1000000}]}','','');
    perform t_ok('FB50 TK chi phí 6427 thiếu trung tâm chi phí bị chặn', false);
  exception when others then perform t_ok('FB50 TK chi phí 6427 thiếu trung tâm chi phí bị chặn', sqlerrm like '%bắt buộc chọn trung tâm chi phí%', sqlerrm); end;
  begin
    perform erp_doc_create(th,'C08','JE','{"date":"2026-11-10","memo":"x","lines":[{"a":"6427","dr":1000000,"cc":"CC700"},{"a":"3388","cr":900000}]}','','');
    perform t_ok('FB50 lệch Nợ – Có bị chặn', false);
  exception when others then perform t_ok('FB50 lệch Nợ – Có bị chặn', sqlerrm like 'Bút toán không cân%', sqlerrm); end;
  begin
    perform erp_doc_create(th,'C08','JE','{"date":"2026-11-25","memo":"x","lines":[{"a":"6427","dr":1000000,"cc":"CC700"},{"a":"3388","cr":1000000}]}','','');
    perform t_ok('Chặn chứng từ ngày sau ngày làm việc', false);
  exception when others then perform t_ok('Chặn chứng từ ngày sau ngày làm việc', sqlerrm like '%sau ngày làm việc%', sqlerrm); end;
  begin
    perform erp_doc_create(ap,'C08','JE','{"date":"2026-11-10","memo":"x","lines":[{"a":"6427","dr":1000000,"cc":"CC700"},{"a":"3388","cr":1000000}]}','','');
    perform t_ok('Kế toán phải trả không lập được FB50 (SU53)', false);
  exception when others then perform t_ok('Kế toán phải trả không lập được FB50 (SU53)', sqlerrm like '%SU53%', sqlerrm); end;

  -- ===== (1) FB50 kỳ 11 → đóng kỳ 11 → ghi vào kỳ 11 bị chặn → đảo sang kỳ 12 =====
  r := erp_doc_create(th,'C08','JE','{"date":"2026-11-10","memo":"Trích chi phí kiểm toán phải trả","lines":[{"a":"6427","dr":2000000,"cc":"CC700","memo":"Phí kiểm toán"},{"a":"3388","cr":2000000}]}','',''); je1 := r->>'id';
  perform t_ok('FB50 lập ở trạng thái chờ duyệt, chưa ghi sổ', r->>'status' = 'pending' and erp_balance('C08','6427') = 0);
  begin perform erp_doc_decide(th,'C08',je1,true,'',''); perform t_ok('Kế toán tổng hợp không tự duyệt FB50', false);
  exception when others then perform t_ok('Kế toán tổng hợp không tự duyệt FB50', true, sqlerrm); end;
  perform erp_doc_decide(ktt,'C08',je1,true,'','');
  perform t_ok('FB50 sau duyệt: ghi sổ ngày 10/11/2026, kỳ 11, TTCP CC700',
    (select j.post_date = '2026-11-10' and j.period = 11 from erp_je j where j.co='C08' and j.doc_id=je1)
    and exists (select 1 from erp_je_line l join erp_je j on j.co=l.co and j.id=l.je_id where j.co='C08' and j.doc_id=je1 and l.acc='6427' and l.cc='CC700'));
  begin perform erp_period_set(th,'C08',2026,11,'+',true,''); perform t_ok('Chỉ KTT được đóng kỳ (OB52)', false);
  exception when others then perform t_ok('Chỉ KTT được đóng kỳ (OB52)', sqlerrm like 'Chỉ Kế toán trưởng%', sqlerrm); end;
  r := erp_doc_create(th,'C08','JE','{"date":"2026-11-10","memo":"Bút toán thứ hai kỳ 11","lines":[{"a":"6428","dr":500000,"cc":"CC100"},{"a":"3388","cr":500000}]}','',''); je2 := r->>'id';
  perform erp_period_set(ktt,'C08',2026,11,'+',true,'');
  begin perform erp_doc_decide(ktt,'C08',je2,true,'',''); perform t_ok('(1) Kỳ 11 đã đóng: duyệt bút toán kỳ 11 bị chặn', false);
  exception when others then perform t_ok('(1) Kỳ 11 đã đóng: duyệt bút toán kỳ 11 bị chặn', sqlerrm like 'Kỳ 11/2026 đã đóng%', sqlerrm); end;
  begin perform erp_post('C08', null, 'TEST', null, null, '[{"a":"112","dr":1},{"a":"111","cr":1}]'::jsonb, ''); perform t_ok('(1) Kỳ 11 đã đóng: erp_post vào kỳ 11 bị chặn', false);
  exception when others then perform t_ok('(1) Kỳ 11 đã đóng: erp_post vào kỳ 11 bị chặn', sqlerrm like 'Kỳ 11/2026 đã đóng%', sqlerrm); end;
  perform erp_doc_decide(ktt,'C08',je2,false,'Kỳ đã khóa sổ, lập lại ở kỳ sau','');
  perform erp_admin_set_state(gv, 'C08', '{"wdate":"2026-12-02"}');
  begin perform erp_doc_create(th,'C08','JE','{"date":"2026-12-02","kind":"rev","revOf":"OB00001","reason":"x"}','',''); perform t_ok('FB08 không đảo chứng từ nghiệp vụ / mở sổ', false);
  exception when others then perform t_ok('FB08 không đảo chứng từ nghiệp vụ / mở sổ', sqlerrm like 'FB08 chỉ đảo%', sqlerrm); end;
  r := erp_doc_create(th,'C08','JE',jsonb_build_object('date','2026-12-02','kind','rev','revOf',je1,'reason','Kiểm toán độc lập đã giảm phí'),'',''); rev := r->>'id';
  begin perform erp_doc_create(th,'C08','JE',jsonb_build_object('date','2026-12-02','kind','rev','revOf',je1,'reason','lần 2'),'','');
    perform t_ok('FB08 không lập hai đề nghị đảo cho một bút toán', false);
  exception when others then perform t_ok('FB08 không lập hai đề nghị đảo cho một bút toán', sqlerrm like '%đã được đảo hoặc đang có đề nghị đảo%', sqlerrm); end;
  perform erp_doc_decide(ktt,'C08',rev,true,'','');
  perform t_ok('(1) Đảo FB08 ghi vào kỳ 12 (ngày 02/12/2026), Nợ/Có đảo ngược',
    (select j.post_date = '2026-12-02' and j.period = 12 from erp_je j where j.co='C08' and j.doc_id=rev)
    and exists (select 1 from erp_je_line l join erp_je j on j.co=l.co and j.id=l.je_id where j.co='C08' and j.doc_id=rev and l.acc='6427' and l.cr=2000000 and l.cc='CC700'));
  perform t_ok('(1) Liên kết hai chiều: bút toán gốc ghi số chứng từ đảo', (select data->>'revBy' from erp_doc where co='C08' and id=je1) = rev
    and (select data->>'revOf' from erp_doc where co='C08' and id=rev) = je1);
  perform t_eq('(1) Sau đảo: số dư TK 6427 = 0', erp_balance('C08','6427'), 0);
  perform t_eq('(1) Sổ kỳ 11 không bị sửa: phát sinh Nợ 6427 kỳ 11 vẫn = 2.000.000',
    (select sum(l.dr) from erp_je_line l join erp_je j on j.co=l.co and j.id=l.je_id where j.co='C08' and j.period=11 and l.acc='6427'), 2000000);

  -- ===== FBS1 trích trước, tự đảo đầu kỳ sau =====
  r := erp_doc_create(th,'C08','JE','{"date":"2026-12-02","kind":"acc","memo":"Trích trước tiền điện tháng 12","lines":[{"a":"6417","dr":3000000,"cc":"CC300"},{"a":"335","cr":3000000}]}','',''); acr := r->>'id';
  perform t_ok('FBS1: ngày tự đảo = 01/01/2027', (select data->>'revDate' from erp_doc where co='C08' and id=acr) = '2027-01-01');
  perform erp_doc_decide(ktt,'C08',acr,true,'','');
  perform t_ok('FBS1: duyệt xong có chứng từ tự đảo ghi ngày 01/01/2027',
    exists (select 1 from erp_doc d join erp_je j on j.co=d.co and j.doc_id=d.id where d.co='C08' and d.data->>'revOf'=acr and (d.data->>'auto')::boolean and j.post_date='2027-01-01'));
  perform t_eq('FBS1: số dư TK 335 sau tự đảo = 0', erp_balance('C08','335'), 0);
  perform t_eq('FBS1: chi phí tháng 12 vẫn ghi nhận 3.000.000',
    (select sum(l.dr) from erp_je_line l join erp_je j on j.co=l.co and j.id=l.je_id where j.co='C08' and j.fy=2026 and j.period=12 and l.acc='6417'), 3000000);

  -- ===== FBCJ quỹ tiền mặt, kiểm quỹ =====
  r := erp_doc_create(tq,'C08','CJ','{"date":"2026-12-02","dir":"out","acc":"6423","cc":"CC700","amount":500000,"person":"Nguyễn Văn A","reason":"Mua văn phòng phẩm"}','',''); cj := r->>'id';
  perform t_ok('FBCJ: phiếu chi chờ KTT duyệt', r->>'status' = 'pending');
  perform erp_doc_decide(ktt,'C08',cj,true,'','');
  perform t_eq('FBCJ: tồn quỹ 111 = 200.000.000 − 500.000', erp_balance('C08','111'), 199500000);
  r := erp_doc_create(tq,'C08','CJ','{"date":"2026-12-02","dir":"out","acc":"6428","cc":"CC100","amount":300000000,"person":"B","reason":"Chi lớn"}','',''); cj := r->>'id';
  begin perform erp_doc_decide(ktt,'C08',cj,true,'',''); perform t_ok('FBCJ: chặn chi làm tồn quỹ âm', false);
  exception when others then perform t_ok('FBCJ: chặn chi làm tồn quỹ âm', sqlerrm like 'Không đủ tồn quỹ%', sqlerrm); end;
  perform erp_doc_decide(ktt,'C08',cj,false,'Vượt tồn quỹ','');
  begin perform erp_doc_create(tq,'C08','CJ','{"date":"2026-12-02","dir":"in","acc":"131","amount":1000000,"person":"C","reason":"x"}','','');
    perform t_ok('FBCJ: không thu tiền mặt ghi thẳng TK 131 (phải qua F-28)', false);
  exception when others then perform t_ok('FBCJ: không thu tiền mặt ghi thẳng TK 131 (phải qua F-28)', sqlerrm like 'TK 131 là tài khoản đối chiếu%', sqlerrm); end;
  begin perform erp_doc_create(tq,'C08','CNT','{"date":"2026-12-02","members":"Thủ quỹ, KTT"}','',''); perform t_ok('Kiểm quỹ: chưa có số kiểm đếm của giảng viên thì chưa lập được', false);
  exception when others then perform t_ok('Kiểm quỹ: chưa có số kiểm đếm của giảng viên thì chưa lập được', sqlerrm like 'Giảng viên chưa nhập%', sqlerrm); end;
  perform erp_admin_set_state(gv, 'C08', '{"cashCount":199300000}');
  r := erp_doc_create(tq,'C08','CNT','{"date":"2026-12-02","members":"Thủ quỹ, KTT, KSNB","reason":"Chưa rõ nguyên nhân"}','',''); cnt := r->>'id';
  perform t_ok('Kiểm quỹ: sổ 199.500.000, thực tế 199.300.000, thiếu 200.000, chờ duyệt',
    r->>'status' = 'pending' and (select (data->>'diff')::numeric from erp_doc where co='C08' and id=cnt) = -200000);
  perform erp_doc_decide(ktt,'C08',cnt,true,'Chờ xử lý trách nhiệm','');
  perform t_eq('Kiểm quỹ: TK 1381 tài sản thiếu chờ xử lý = 200.000', erp_balance('C08','1381'), 200000);
  perform t_eq('Kiểm quỹ: TK 111 khớp số kiểm đếm', erp_balance('C08','111'), 199300000);

  -- ===== Tạm ứng – quyết toán =====
  r := erp_doc_create(kho,'C08','ADV','{"date":"2026-12-02","amount":2000000,"purpose":"Công tác phí đi Đà Lạt giao hàng"}','',''); adv := r->>'id';
  begin perform erp_doc_create(tq,'C08','CJ',jsonb_build_object('date','2026-12-02','adv',adv),'',''); perform t_ok('Tạm ứng chưa duyệt thì Thủ quỹ chưa chi', false);
  exception when others then perform t_ok('Tạm ứng chưa duyệt thì Thủ quỹ chưa chi', sqlerrm like '%chưa được duyệt%', sqlerrm); end;
  perform erp_doc_decide(ktt,'C08',adv,true,'','');
  r := erp_doc_create(tq,'C08','CJ',jsonb_build_object('date','2026-12-02','adv',adv),'','');
  perform t_ok('Chi tạm ứng: ghi sổ ngay, Nợ 141 chi tiết người nhận = 2.000.000',
    r->>'status' = 'posted' and erp_balance_p('C08','141','tst_kho') = 2000000 and (select status from erp_doc where co='C08' and id=adv) = 'paid');
  begin perform erp_doc_create(kho,'C08','ADV','{"date":"2026-12-02","amount":1000000,"purpose":"lần 2"}','',''); perform t_ok('Chưa quyết toán khoản cũ thì không tạm ứng tiếp', false);
  exception when others then perform t_ok('Chưa quyết toán khoản cũ thì không tạm ứng tiếp', sqlerrm like 'Bạn còn khoản tạm ứng%', sqlerrm); end;
  begin perform erp_doc_create(mh,'C08','ADS',jsonb_build_object('date','2026-12-02','adv',adv,'lines','[{"a":"6417","cc":"CC300","amount":100000,"memo":"x"}]'::jsonb),'','');
    perform t_ok('Chỉ người nhận tạm ứng lập giấy thanh toán', false);
  exception when others then perform t_ok('Chỉ người nhận tạm ứng lập giấy thanh toán', sqlerrm like 'Chỉ người nhận tạm ứng%', sqlerrm); end;
  r := erp_doc_create(kho,'C08','ADS',jsonb_build_object('date','2026-12-02','adv',adv,'lines',
         '[{"a":"6417","cc":"CC300","amount":1200000,"memo":"Vé xe HĐ 0012345"},{"a":"6418","cc":"CC300","amount":500000,"memo":"Lưu trú HĐ 0045678"}]'::jsonb),'',''); ads := r->>'id';
  perform erp_doc_decide(ktt,'C08',ads,true,'','');
  perform t_ok('Quyết toán: 141 về 0, nộp lại quỹ 300.000, tạm ứng chuyển trạng thái đã quyết toán',
    erp_balance_p('C08','141','tst_kho') = 0 and erp_balance('C08','111') = 199300000 - 2000000 + 300000
    and (select status from erp_doc where co='C08' and id=adv) = 'settled');

  -- ===== (2) Ngân hàng qua TK 113, sao kê, đối chiếu =====
  -- Các khoản cài sẵn tháng 11 đã phát hành khi tua sang 02/12
  perform t_eq('Sao kê: 3 dòng cài sẵn tháng 11 đã phát hành khi tua ngày', (select count(*) from erp_bank_line where co='C08' and kind in ('fee','int','unk')), 3);
  r := erp_doc_create(kho,'C08','PR','{"date":"2026-12-02","reason":"x","items":[{"mat":"HH04","qty":10}]}','',''); pr := r->>'id';
  perform erp_doc_decide(ktt,'C08',pr,true,'','');
  r := erp_doc_create(mh,'C08','PO',jsonb_build_object('pr',pr,'vendor','NCC01','date','2026-12-02','items','[{"mat":"HH04","qty":10,"price":290000}]'::jsonb),'',''); po := r->>'id';
  perform erp_doc_decide(ktt,'C08',po,true,'','');
  perform erp_doc_create(kho,'C08','GR',jsonb_build_object('po',po,'date','2026-12-02','dn','PG1','deliverer','A','items','[{"line":0,"qty":10}]'::jsonb),'','');
  r := erp_doc_create(ap,'C08','IV',jsonb_build_object('po',po,'date','2026-12-02','invSym','1C26TSM','invNo','901','items','[{"line":0,"qty":10,"price":290000}]'::jsonb),'',''); iv := r->>'id';
  r := erp_doc_create(ap,'C08','PAY',jsonb_build_object('iv',iv,'date','2026-12-02','acc','112','amount',3132000),'',''); pay := r->>'id';
  perform erp_doc_decide(ktt,'C08',pay,true,'','');
  perform t_ok('Chi chuyển khoản ghi Có TK 113 (tiền đang chuyển), TK 112 chưa đổi',
    erp_balance('C08','113') = -3132000 and erp_balance('C08','112') = 3000000000);
  perform t_eq('Sao kê chưa có dòng chi khi ngân hàng chưa hạch toán (cùng ngày)', erp_bank_issue('C08'), 0);
  perform erp_admin_set_state(gv, 'C08', '{"wdate":"2026-12-05"}');
  select id into ln from erp_bank_line where co='C08' and ref_doc = pay;
  perform t_ok('Tua ngày: sao kê phát hành dòng chi ngày 03/12/2026', ln is not null and (select vdate = '2026-12-03' and amt = -3132000 from erp_bank_line where co='C08' and id=ln));
  begin perform erp_bank_match(ap,'C08',ln,'{}',''); perform t_ok('Kế toán phải trả không xử lý được sao kê (FF67)', false);
  exception when others then perform t_ok('Kế toán phải trả không xử lý được sao kê (FF67)', sqlerrm like '%FF67%', sqlerrm); end;
  perform erp_bank_match(th,'C08',ln,'{}','');
  perform t_ok('Khớp dòng chi: TK 113 về 0, TK 112 giảm 3.132.000', erp_balance('C08','113') = 0 and erp_balance('C08','112') = 3000000000 - 3132000);
  begin perform erp_bank_match(th,'C08',ln,'{}',''); perform t_ok('Không khớp một dòng sao kê hai lần', false);
  exception when others then perform t_ok('Không khớp một dòng sao kê hai lần', sqlerrm like '%đã được xử lý%', sqlerrm); end;
  -- Đối chiếu: số dư sao kê = số dư đầu kỳ + các dòng sao kê; chênh lệch với sổ TK 112 = các dòng chưa ghi sổ
  stmt := 3000000000 + (select sum(amt) from erp_bank_line where co='C08');
  bk := erp_balance('C08','112');
  select count(*), coalesce(sum(amt),0) into nunm, unm from erp_bank_line where co='C08' and status='open';
  perform t_ok('(2) Đối chiếu ngân hàng: đúng 3 khoản chênh lệch (tiền về chưa rõ 15.000.000, phí −55.000, lãi 1.250.000)',
    nunm = 3 and unm = 15000000 - 55000 + 1250000
    and (select array_agg(kind order by kind) from erp_bank_line where co='C08' and status='open') = array['fee','int','unk'], nunm || ' / ' || unm);
  perform t_ok('(2) Số dư sao kê = sổ TK 112 + các khoản chưa ghi sổ', stmt = bk + unm, stmt || ' vs ' || bk || ' + ' || unm);
  select id into ln from erp_bank_line where co='C08' and kind='unk';
  perform erp_bank_match(th,'C08',ln,'{"cust":"KH02"}','');
  perform t_eq('Tiền về được xác định của KH02: Có 131 KH02', erp_balance_p('C08','131','KH02'), -15000000);
  select id into ln from erp_bank_line where co='C08' and kind='fee'; perform erp_bank_match(th,'C08',ln,'{}','');
  select id into ln from erp_bank_line where co='C08' and kind='int'; perform erp_bank_match(th,'C08',ln,'{}','');
  perform t_eq('Phí ngân hàng vào 6427 (CC700)', (select sum(l.dr) from erp_je_line l join erp_je j on j.co=l.co and j.id=l.je_id where l.co='C08' and j.doc_type='BS' and l.acc='6427' and l.cc='CC700'), 55000);
  perform t_eq('Lãi tiền gửi vào 515', erp_balance('C08','515'), -1250000);
  perform t_ok('Sau khi khớp hết: số dư sao kê = sổ TK 112, không còn dòng chờ',
    (3000000000 + (select sum(amt) from erp_bank_line where co='C08')) = erp_balance('C08','112')
    and not exists (select 1 from erp_bank_line where co='C08' and status='open'));

  -- ===== Bất biến =====
  perform t_ok('Mọi bút toán cân Nợ = Có', not exists (select 1 from erp_je_line where co='C08' group by je_id having sum(dr) <> sum(cr)));
  perform t_ok('Mọi dòng TK chi phí 64x có trung tâm chi phí',
    not exists (select 1 from erp_je_line l join erp_acct a on a.code=l.acc where l.co='C08' and a.cc_req and l.cc is null));
  perform t_ok('Mọi dòng TK 141 có người nhận tạm ứng', not exists (select 1 from erp_je_line where co='C08' and acc='141' and partner is null));
  perform t_ok('Bản sao data.je trùng sổ cái (số dòng)',
    (select count(*) from erp_doc d, jsonb_array_elements(d.data->'je') x where d.co='C08' and jsonb_typeof(d.data->'je')='array')
    = (select count(*) from erp_je_line where co='C08'));
  perform t_ok('anon không gọi được erp_bank_issue, erp_bank_seed', not has_function_privilege('anon','erp_bank_issue(text)','execute')
    and not has_function_privilege('anon','erp_bank_seed(text)','execute'));
  perform t_ok('anon không đọc được bảng sao kê, kỳ kế toán', not has_table_privilege('anon','erp_bank_line','select')
    and not has_table_privilege('anon','erp_period_close','select'));
  r := erp_sync(th,'*',null);
  perform t_ok('erp_sync: sinh viên nhận ngày làm việc, kỳ đã đóng, sao kê; không nhận số kiểm đếm quỹ',
    r->'md'->'C08'->'state'->>'wdate' = '2026-12-05' and jsonb_array_length(r->'md'->'C08'->'periods') = 1
    and jsonb_array_length(r->'md'->'C08'->'bank') = 4 and r->'adm' = 'null'::jsonb);

  -- Dọn dẹp
  perform erp_purge_co('C08');
  delete from erp_session where user_id in (select id from erp_user where username like 'tst\_%') or token::text = gv;
  delete from erp_user where username like 'tst\_%';
  update erp_cfg set v = cfg0 where k = 'main';
  update erp_co_state set wdate = coalesce(wd0, current_date), cash_count = null where co = 'C08';
  perform erp_bank_seed('C08');
end $$;

drop function t_eq(text,numeric,numeric);
drop function t_ok(text,boolean,text);
select n, case when ok then 'ĐẠT' else 'KHÔNG ĐẠT' end kq, name, left(detail,160) detail from tst_p3 order by n;
