-- =====================================================================
-- Kiểm thử P1 – lõi sổ cái. CHỈ CHẠY TRÊN erp-lab-dev (xóa sạch dữ liệu C08).
-- Chạy: dán toàn bộ vào SQL Editor của erp-lab-dev. Kết quả: bảng (ca kiểm thử, đạt, chi tiết).
-- Số kỳ vọng tính tay với thuế suất GTGT 8%, dung sai giá 5%.
-- =====================================================================
drop table if exists tst_p1;
create table tst_p1(n serial, name text, ok boolean, detail text);
alter table tst_p1 enable row level security;
create or replace function t_ok(p_name text, p_ok boolean, p_detail text default '') returns void language sql as
$$ insert into tst_p1(name, ok, detail) values (p_name, coalesce(p_ok,false), coalesce(p_detail,'')) $$;
create or replace function t_eq(p_name text, p_got numeric, p_exp numeric) returns void language sql as
$$ select t_ok(p_name, p_got = p_exp, 'được ' || coalesce(p_got::text,'null') || ', kỳ vọng ' || p_exp) $$;

do $$
declare
  cfg0 jsonb; wd0 date; kho text; mh text; kd text; kt text; ktt text; r jsonb; pr text; po text; gr text; iv text; pay text;
  so1 text; so2 text; so3 text; dl text; bi text; rc text;
begin
  select v into cfg0 from erp_cfg where k = 'main';
  update erp_cfg set v = v || '{"tol":5,"poAuto":0,"credit":true,"selfApprove":false,"vat":0.08,"bankClear":false}' where k = 'main';
  -- Từ P3: ngày ghi sổ = ngày làm việc; kiểm thử P1/P2 chạy trong tháng 11/2026, ngân hàng ghi thẳng 112 (bankClear = false)
  select wdate into wd0 from erp_co_state where co = 'C08';
  update erp_co_state set wdate = '2026-11-30' where co = 'C08';
  perform erp_purge_co('C08');
  delete from erp_user where username like 'tst\_%';
  insert into erp_user(username, full_name, pass_hash, co, role, must_change) values
    ('tst_kho','Thủ kho thử', 'x', 'C08','KHO', false), ('tst_mh','Mua hàng thử','x','C08','MH',false),
    ('tst_kd','Kinh doanh thử','x','C08','KD',false), ('tst_kt','Kế toán thử','x','C08','KT',false),
    ('tst_ktt','KTT thử','x','C08','KTT',false);
  insert into erp_session(user_id, expires_at) select id, now() + interval '1 hour' from erp_user where username like 'tst\_%';
  select s.token::text into kho from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_kho';
  select s.token::text into mh  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_mh';
  select s.token::text into kd  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_kd';
  select s.token::text into kt  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_kt';
  select s.token::text into ktt from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_ktt';

  perform t_eq('Mở sổ: tổng tài sản đầu kỳ = 3.809.000.000', (select sum(dr) from erp_je_line where co='C08'), 3809000000);

  -- ===== Buổi 1: Mua hàng – Thanh toán =====
  r := erp_doc_create(kho,'C08','PR','{"date":"2026-11-02","need":"2026-11-09","reason":"Tồn dưới mức","items":[{"mat":"HH01","qty":10},{"mat":"HH02","qty":20}]}','',''); pr := r->>'id';
  perform t_ok('ME51N lập đề nghị mua → chờ duyệt', r->>'status' = 'pending');
  perform erp_doc_decide(ktt,'C08',pr,true,'Đồng ý','');
  r := erp_doc_create(mh,'C08','PO',jsonb_build_object('pr',pr,'vendor','NCC02','date','2026-11-03','need','2026-11-09','status','approved',
        'items',jsonb_build_array(jsonb_build_object('mat','HH01','qty',10,'price',17945000),jsonb_build_object('mat','HH02','qty',20,'price',2522000))),'','');
  po := r->>'id';
  perform t_ok('ME21N: trình duyệt gửi status=approved vẫn phải chờ KTT duyệt', r->>'status' = 'pending', r->>'status');
  perform erp_doc_decide(ktt,'C08',po,true,'','');
  r := erp_doc_create(kho,'C08','GR',jsonb_build_object('po',po,'date','2026-11-05','dn','PGH-01','deliverer','Anh Bình',
        'items',jsonb_build_array(jsonb_build_object('line',0,'qty',8),jsonb_build_object('line',1,'qty',20)),
        'je',jsonb_build_array(jsonb_build_object('a','111','dr',1000000000),jsonb_build_object('a','4111','cr',1000000000))),'','');
  gr := r->>'id';
  perform t_eq('Tấn công: GR kèm bút toán giả 111/4111 – TK 111 không đổi', erp_balance('C08','111'), 200000000);
  perform t_eq('MIGO: Nợ 156 = 8×17.945.000 + 20×2.522.000', (select sum(dr) from erp_je_line l join erp_je j on j.co=l.co and j.id=l.je_id where l.co='C08' and j.doc_id=gr and l.acc='156'), 194000000);
  begin
    perform erp_doc_create(kho,'C08','GR',jsonb_build_object('po',po,'date','2026-11-05','dn','PGH-02','deliverer','A','items',jsonb_build_array(jsonb_build_object('line',0,'qty',3))),'','');
    perform t_ok('Chặn nhập vượt đơn mua (còn 2, nhập 3)', false);
  exception when others then perform t_ok('Chặn nhập vượt đơn mua (còn 2, nhập 3)', sqlerrm like 'Nhập vượt đơn mua%', sqlerrm); end;
  r := erp_doc_create(kt,'C08','IV',jsonb_build_object('po',po,'date','2026-11-06','invSym','1C26TAA','invNo','123','status','posted',
        'items',jsonb_build_array(jsonb_build_object('line',0,'qty',8,'price',17945000),jsonb_build_object('line',1,'qty',20,'price',2723760))),'','');
  iv := r->>'id';
  perform t_ok('MIRO: lệch giá 8% > 5% bị khóa dù trình duyệt gửi status=posted', r->>'status' = 'blocked', r->>'status');
  perform t_eq('MIRO: Có 331 = chênh lệch 4.035.200 + thuế 15.842.816', (select sum(cr) from erp_je_line l join erp_je j on j.co=l.co and j.id=l.je_id where l.co='C08' and j.doc_id=iv and l.acc='331'), 19878016);
  begin
    perform erp_doc_create(kt,'C08','IV',jsonb_build_object('po',po,'date','2026-11-06','invSym','1c26taa','invNo','0123','items',jsonb_build_array(jsonb_build_object('line',0,'qty',0))),'','');
    perform t_ok('Chặn hóa đơn trùng (ký hiệu, số, NCC)', false);
  exception when others then perform t_ok('Chặn hóa đơn trùng (ký hiệu, số, NCC)', sqlerrm like 'Hóa đơn trùng%', sqlerrm); end;
  begin
    perform erp_doc_create(kt,'C08','PAY',jsonb_build_object('iv',iv,'date','2026-11-07','acc','112','amount',1000000),'','');
    perform t_ok('Chặn đề nghị chi khi hóa đơn đang khóa', false);
  exception when others then perform t_ok('Chặn đề nghị chi khi hóa đơn đang khóa', true, sqlerrm); end;
  perform erp_doc_decide(ktt,'C08',iv,true,'NCC xác nhận giá mới','');
  r := erp_doc_create(kho,'C08','GR',jsonb_build_object('po',po,'date','2026-11-08','dn','PGH-02','deliverer','Anh Bình','items',jsonb_build_array(jsonb_build_object('line',0,'qty',2))),'','');
  r := erp_doc_create(kt,'C08','PAY',jsonb_build_object('iv',iv,'date','2026-11-09','acc','112','amount',100000000),'',''); pay := r->>'id';
  begin
    perform erp_doc_decide(kt,'C08',pay,true,'','');
    perform t_ok('Kế toán công nợ không được duyệt chi', false);
  exception when others then perform t_ok('Kế toán công nợ không được duyệt chi', true, sqlerrm); end;
  perform erp_doc_decide(ktt,'C08',pay,true,'','');
  perform t_eq('Buổi 1: số dư 112', erp_balance('C08','112'), 2900000000);
  perform t_eq('Buổi 1: phải trả NCC02', erp_balance_p('C08','331','NCC02'), -149768016);
  perform t_eq('Buổi 1: thuế GTGT được khấu trừ', erp_balance('C08','1331'), 15842816);
  perform t_eq('Buổi 1: tồn HH01 giá trị', (select value from erp_val where co='C08' and mat='HH01'), 549450000);
  perform t_eq('Buổi 1: tồn HH02 giá trị (gồm chênh lệch giá)', (select value from erp_val where co='C08' and mat='HH02'), 158475200);

  -- ===== Buổi 2: Bán hàng – Thu tiền =====
  r := erp_doc_create(kd,'C08','SO','{"cust":"KH01","custPo":"DH-BX-01","date":"2026-11-10","need":"2026-11-12","items":[{"mat":"HH01","qty":5,"price":23900000},{"mat":"HH02","qty":10,"price":3450000},{"mat":"HH04","qty":10,"price":420000}]}','',''); so1 := r->>'id';
  perform t_ok('VA01 Biển Xanh 170.856.000 trong hạn mức → xác nhận', r->>'status' = 'approved', r->>'status');
  r := erp_doc_create(kd,'C08','SO','{"cust":"KH03","custPo":"DH-PH-01","date":"2026-11-10","status":"approved","items":[{"mat":"HH01","qty":6,"price":23900000}]}','',''); so2 := r->>'id';
  perform t_ok('VA01 Phước Hải 154.872.000 > 150 triệu → khóa tín dụng dù trình duyệt gửi approved', r->>'status' = 'blocked', r->>'status');
  perform erp_doc_decide(ktt,'C08',so2,true,'Khách quen, đã cam kết trả','');
  r := erp_doc_create(kho,'C08','DL',jsonb_build_object('so',so1,'date','2026-11-11','receiver','Chị Lan','items',
        jsonb_build_array(jsonb_build_object('line',0,'qty',5),jsonb_build_object('line',1,'qty',10),jsonb_build_object('line',2,'qty',10))),'',''); dl := r->>'id';
  perform t_eq('VL01N: giá vốn bình quân = 91.575.000 + 26.412.533 + 2.900.000', (select sum(dr) from erp_je_line l join erp_je j on j.co=l.co and j.id=l.je_id where l.co='C08' and j.doc_id=dl and l.acc='632'), 120887533);
  r := erp_doc_create(kd,'C08','SO','{"cust":"KH02","custPo":"DH-HT-01","date":"2026-11-10","items":[{"mat":"HH03","qty":20,"price":4990000}]}','',''); so3 := r->>'id';
  begin
    perform erp_doc_create(kho,'C08','DL',jsonb_build_object('so',so3,'date','2026-11-11','receiver','A','items',jsonb_build_array(jsonb_build_object('line',0,'qty',20))),'','');
    perform t_ok('Chặn xuất vượt tồn (HH03 còn 15)', false);
  exception when others then perform t_ok('Chặn xuất vượt tồn (HH03 còn 15)', sqlerrm like 'Không đủ tồn kho%', sqlerrm); end;
  r := erp_doc_create(kt,'C08','BI',jsonb_build_object('dl',dl,'date','2026-11-11'),'',''); bi := r->>'id';
  begin
    perform erp_doc_create(kt,'C08','BI',jsonb_build_object('dl',dl,'date','2026-11-11'),'','');
    perform t_ok('Chặn lập hóa đơn hai lần cho một phiếu xuất', false);
  exception when others then perform t_ok('Chặn lập hóa đơn hai lần cho một phiếu xuất', true, sqlerrm); end;
  r := erp_doc_create(kt,'C08','RC',jsonb_build_object('bi',bi,'date','2026-11-12','acc','112','amount',85428000,'ref','GBC-778'),'',''); rc := r->>'id';
  perform erp_doc_decide(ktt,'C08',rc,true,'','');
  perform t_eq('Buổi 2: phải thu Biển Xanh còn 50%', erp_balance_p('C08','131','KH01'), 85428000);
  perform t_eq('Buổi 2: doanh thu 511', erp_balance('C08','511'), -158200000);
  perform t_eq('Buổi 2: thuế GTGT đầu ra', erp_balance('C08','33311'), -12656000);
  perform t_eq('Buổi 2: số dư 112', erp_balance('C08','112'), 2985428000);

  -- ===== Bất biến =====
  perform t_ok('BB2: mọi chứng từ kế toán cân Nợ = Có',
    not exists (select 1 from erp_je_line where co='C08' group by je_id having sum(dr) <> sum(cr)));
  perform t_ok('BB3: sổ kho (erp_val) = số dư TK 156',
    (select sum(value) from erp_val where co='C08') = erp_balance('C08','156'));
  perform t_ok('BB3: sổ kho theo vật tư = dòng 156 theo vật tư',
    not exists (select 1 from erp_val v where co='C08' and value <> (select coalesce(sum(dr-cr),0) from erp_je_line where co='C08' and acc='156' and mat=v.mat)));
  perform t_ok('BB3: số lượng tồn = tổng số lượng trên dòng 156',
    not exists (select 1 from erp_val v where co='C08' and qty <> (select coalesce(sum(case when dr>0 then qty else -qty end),0) from erp_je_line where co='C08' and acc='156' and mat=v.mat)));
  perform t_ok('BB3: mọi dòng 131/331 đều có đối tượng',
    not exists (select 1 from erp_je_line where co='C08' and acc in ('131','331') and partner is null));
  perform t_ok('BB1: bản sao data.je trên chứng từ trùng sổ cái',
    not exists (
      select d.id from erp_doc d where d.co='C08' and jsonb_typeof(d.data->'je')='array'
       group by d.id having
         (select coalesce(sum(coalesce((x->>'dr')::numeric,0)-coalesce((x->>'cr')::numeric,0)) filter (where x->>'a'='156'),0)
            from erp_doc d2, jsonb_array_elements(d2.data->'je') x where d2.co='C08' and d2.id=d.id)
       <> (select coalesce(sum(l.dr-l.cr) filter (where l.acc='156'),0) from erp_je j join erp_je_line l on l.co=j.co and l.je_id=j.id where j.co='C08' and j.doc_id=d.id)
    ));
  perform t_eq('BB1: số dòng bút toán trên chứng từ = số dòng sổ cái',
    (select count(*) from erp_doc d, jsonb_array_elements(d.data->'je') x where d.co='C08' and jsonb_typeof(d.data->'je')='array'),
    (select count(*) from erp_je_line where co='C08'));
  begin
    delete from erp_je_line where co = 'C08' and ln = 1;
    perform t_ok('BB5: không xóa được dòng bút toán đã ghi sổ', false);
  exception when others then perform t_ok('BB5: không xóa được dòng bút toán đã ghi sổ', sqlerrm like 'Chứng từ kế toán đã ghi sổ%', sqlerrm); end;
  begin
    update erp_je_line set dr = dr + 1 where co = 'C08' and dr > 0;
    perform t_ok('BB5: không sửa được số tiền đã ghi sổ', false);
  exception when others then perform t_ok('BB5: không sửa được số tiền đã ghi sổ', true, sqlerrm); end;
  begin
    perform erp_post('C08', null, 'TEST', '2026-11-12', null, '[{"a":"111","dr":100},{"a":"112","cr":99}]'::jsonb, '');
    perform t_ok('erp_post từ chối bút toán lệch', false);
  exception when others then perform t_ok('erp_post từ chối bút toán lệch', sqlerrm like 'Bút toán không cân%', sqlerrm); end;
  begin
    perform erp_post('C08', null, 'TEST', '2026-11-12', null, '[{"a":"131","dr":100},{"a":"112","cr":100}]'::jsonb, '');
    perform t_ok('erp_post đòi đối tượng cho TK 131', false);
  exception when others then perform t_ok('erp_post đòi đối tượng cho TK 131', true, sqlerrm); end;

  -- ===== Kiểm soát: tự duyệt, chi vượt số dư =====
  update erp_user set extra = '{KT}' where username = 'tst_ktt';
  r := erp_doc_create(ktt,'C08','PAY',jsonb_build_object('iv',iv,'date','2026-11-12','acc','111','amount',1000000),'',''); pay := r->>'id';
  begin
    perform erp_doc_decide(ktt,'C08',pay,true,'','');
    perform t_ok('BB6: KTT kiêm KT không tự duyệt phiếu chi mình lập', false);
  exception when others then perform t_ok('BB6: KTT kiêm KT không tự duyệt phiếu chi mình lập', sqlerrm like 'Vi phạm bất kiêm nhiệm%', sqlerrm); end;
  update erp_user set extra = '{}' where username = 'tst_ktt';
  perform erp_post('C08', null, 'TEST', '2026-11-12', null, '[{"a":"112","dr":150000000},{"a":"111","cr":150000000}]'::jsonb, 'Nộp tiền mặt vào ngân hàng (thiết lập ca thử)');
  r := erp_doc_create(kt,'C08','PAY',jsonb_build_object('iv',iv,'date','2026-11-12','acc','111','amount',60000000),'',''); pay := r->>'id';
  begin
    perform erp_doc_decide(ktt,'C08',pay,false,'','');
    perform t_ok('Từ chối phải có lý do', false);
  exception when others then perform t_ok('Từ chối phải có lý do', sqlerrm like 'Hãy ghi lý do%', sqlerrm); end;
  begin
    perform erp_doc_decide(ktt,'C08',pay,true,'','');
    perform t_ok('Chặn chi vượt số dư tiền mặt (còn 50 triệu, chi 60 triệu)', false);
  exception when others then perform t_ok('Chặn chi vượt số dư tiền mặt (còn 50 triệu, chi 60 triệu)', sqlerrm like 'Không đủ số dư%', sqlerrm); end;

  -- ===== Phân quyền tầng cơ sở dữ liệu =====
  perform t_ok('anon không gọi được erp_post', not has_function_privilege('anon','erp_post(text,text,text,date,uuid,jsonb,text)','execute'));
  perform t_ok('anon không gọi được erp_val_out', not has_function_privilege('anon','erp_val_out(text,text,numeric)','execute'));
  perform t_ok('anon không đọc được erp_je_line', not has_table_privilege('anon','erp_je_line','select'));
  perform t_ok('anon gọi được erp_doc_create (cửa API hợp lệ)', has_function_privilege('anon','erp_doc_create(text,text,text,jsonb,text,text)','execute'));
  begin
    perform erp_doc_create(kho,'C07','PR','{"date":"2026-11-02","reason":"x","items":[{"mat":"HH01","qty":1}]}','','');
    perform t_ok('Sinh viên C08 không ghi được chứng từ cho C07', false);
  exception when others then perform t_ok('Sinh viên C08 không ghi được chứng từ cho C07', true, sqlerrm); end;
  begin
    perform erp_doc_create(kho,'C08','PO','{"date":"2026-11-02"}','','');
    perform t_ok('Thủ kho không lập được đơn mua (SU53)', false);
  exception when others then perform t_ok('Thủ kho không lập được đơn mua (SU53)', sqlerrm like '%SU53%', sqlerrm); end;

  -- Dọn dẹp: trả C08 về số dư đầu kỳ
  perform erp_purge_co('C08');
  delete from erp_session where user_id in (select id from erp_user where username like 'tst\_%');
  delete from erp_user where username like 'tst\_%';
  update erp_cfg set v = cfg0 where k = 'main';
  update erp_co_state set wdate = wd0 where co = 'C08';
end $$;

drop function t_eq(text,numeric,numeric);
drop function t_ok(text,boolean,text);
select n, case when ok then 'ĐẠT' else 'KHÔNG ĐẠT' end kq, name, detail from tst_p1 order by n;
