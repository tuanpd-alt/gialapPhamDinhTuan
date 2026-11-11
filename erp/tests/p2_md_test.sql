-- =====================================================================
-- Kiểm thử P2 – tổ chức, vai trò, quyền, dữ liệu gốc. CHỈ CHẠY TRÊN erp-lab-dev (xóa dữ liệu C08, dữ liệu gốc thêm mới ở C08).
-- =====================================================================
-- Bảng kết quả và hàm kiểm thử là đối tượng tạm (pg_temp): tự mất khi hết phiên, không lộ qua API (RV-29)
create temp table tst_p2(n serial, name text, ok boolean, detail text);
create function pg_temp.t_ok(p_name text, p_ok boolean, p_detail text default '') returns void language sql as
$$ insert into tst_p2(name, ok, detail) values (p_name, coalesce(p_ok,false), coalesce(p_detail,'')) $$;

do $$
declare
  cfg0 jsonb; wd0 date; kho text; mh text; kd text; kt text; ktt text; ap text; r jsonb; m text; vend text; pr text; po text; so text; dl text; iv text; pay text; chg bigint;
  bank0 text; s jsonb; uids uuid[];
begin
  if coalesce((select v->>'env' from erp_cfg where k = 'main'),'') <> 'dev' then
    raise exception 'Kiểm thử chỉ chạy trên cơ sở dữ liệu phát triển (erp_cfg.main.env = "dev"). Dừng để bảo vệ dữ liệu lớp học.';
  end if;
  select v into cfg0 from erp_cfg where k = 'main';
  update erp_cfg set v = v || '{"tol":5,"poAuto":0,"credit":true,"selfApprove":false,"vat":0.08,"bankClear":false}' where k = 'main';
  -- Từ P3: ngày ghi sổ = ngày làm việc; kiểm thử P1/P2 chạy trong tháng 11/2026, ngân hàng ghi thẳng 112 (bankClear = false)
  select wdate into wd0 from erp_co_state where co = 'C08';
  update erp_co_state set wdate = '2026-11-30' where co = 'C08';
  perform erp_purge_co('C08');
  delete from erp_md_change where co = 'C08';
  delete from erp_price where co = 'C08' and by is not null;
  delete from erp_mat where co = 'C08' and code not in ('HH01','HH02','HH03','HH04','HH05','NV01','NV02','NV03','NV04','NV05','NV06','TP01','TP02','DV01','DV02');
  delete from erp_partner where co = 'C08' and code not in ('NCC01','NCC02','NCC03','NCC04','NCC05','NCC06','KH01','KH02','KH03','KH04','KH05','KH06');
  update erp_partner set bank_acc = '0071 0012 3456 02', active = true where co = 'C08' and code = 'NCC02';
  update erp_partner set active = true where co = 'C08' and code = 'KH02';
  delete from erp_user where username like 'tst\_%';
  insert into erp_user(username, full_name, pass_hash, co, role, must_change) values
    ('tst_kho','Thủ kho thử','x','C08','KHO',false), ('tst_mh','Mua hàng thử','x','C08','MH',false),
    ('tst_kd','Kinh doanh thử','x','C08','KD',false), ('tst_kt','Kế toán thử','x','C08','KT',false),
    ('tst_ktt','KTT thử','x','C08','KTT',false);
  insert into erp_session(user_id, expires_at) select id, now() + interval '1 hour' from erp_user where username like 'tst\_%';
  select s.token::text into kho from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_kho';
  select s.token::text into mh  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_mh';
  select s.token::text into kd  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_kd';
  select s.token::text into kt  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_kt';
  select s.token::text into ktt from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_ktt';

  -- 1. Vật tư mới: tạo, mua, bán được
  r := erp_md_save(mh,'C08','MAT','','{"name":"Ổ cứng di động 1TB","unit":"Cái","mtype":"HH","buy_price":1200000,"sell_price":1650000,"min_stock":5,"valid_from":"2026-01-01"}','');
  m := r->>'key';
  perform pg_temp.t_ok('MM01: Mua hàng tạo vật tư mới, hệ thống cấp mã HH06', m = 'HH06', m);
  perform pg_temp.t_ok('MM01: vật tư hàng hóa tự gắn TK 156 và kho 1003', (select acc = '156' and sloc = '1003' from erp_mat where co='C08' and code=m));
  begin perform erp_md_save(mh,'C08','MAT','','{"name":"ổ cứng di động 1tb","unit":"Cái","mtype":"HH"}',''); perform pg_temp.t_ok('MM01: chặn trùng tên vật tư', false);
  exception when others then perform pg_temp.t_ok('MM01: chặn trùng tên vật tư', sqlerrm like 'Đã có vật tư cùng tên%', sqlerrm); end;
  begin perform erp_md_save(kho,'C08','MAT','','{"name":"Thử","unit":"Cái","mtype":"HH"}',''); perform pg_temp.t_ok('MM01: Thủ kho không được tạo vật tư (SU53)', false);
  exception when others then perform pg_temp.t_ok('MM01: Thủ kho không được tạo vật tư (SU53)', sqlerrm like '%SU53%', sqlerrm); end;
  r := erp_doc_create(kho,'C08','PR',jsonb_build_object('date','2026-11-02','reason','Mặt hàng mới','items',jsonb_build_array(jsonb_build_object('mat',m,'qty',10))),'',''); pr := r->>'id';
  perform erp_doc_decide(ktt,'C08',pr,true,'','');
  r := erp_doc_create(mh,'C08','PO',jsonb_build_object('pr',pr,'vendor','NCC01','date','2026-11-03','items',jsonb_build_array(jsonb_build_object('mat',m,'qty',10,'price',1200000))),'',''); po := r->>'id';
  perform erp_doc_decide(ktt,'C08',po,true,'','');
  perform erp_doc_create(kho,'C08','GR',jsonb_build_object('po',po,'date','2026-11-04','dn','PGH','deliverer','A','items',jsonb_build_array(jsonb_build_object('line',0,'qty',10))),'','');
  r := erp_doc_create(kd,'C08','SO',jsonb_build_object('cust','KH01','custPo','DH1','date','2026-11-05','items',jsonb_build_array(jsonb_build_object('mat',m,'qty',4,'price',1650000))),'',''); so := r->>'id';
  r := erp_doc_create(kho,'C08','DL',jsonb_build_object('so',so,'date','2026-11-05','receiver','B','items',jsonb_build_array(jsonb_build_object('line',0,'qty',4))),'',''); dl := r->>'id';
  r := erp_doc_create(kt,'C08','BI',jsonb_build_object('dl',dl,'date','2026-11-05'),'','');
  perform pg_temp.t_ok('Vật tư mới đi trọn mua → nhập → bán → xuất → hóa đơn; tồn còn 6, giá trị 7.200.000',
    (select qty = 6 and value = 7200000 from erp_val where co='C08' and mat=m));
  begin
    perform erp_doc_create(kho,'C08','PR','{"date":"2026-11-02","reason":"x","items":[{"mat":"TP01","qty":1}]}','','');
    perform pg_temp.t_ok('ME51N: không mua ngoài thành phẩm TP01', false);
  exception when others then perform pg_temp.t_ok('ME51N: không mua ngoài thành phẩm TP01', sqlerrm like '%không mua ngoài được%', sqlerrm); end;
  -- linh kiện (NVL) mua về ghi Nợ 152
  r := erp_doc_create(kho,'C08','PR','{"date":"2026-11-02","reason":"Linh kiện","items":[{"mat":"NV04","qty":20}]}','',''); pr := r->>'id';
  perform erp_doc_decide(ktt,'C08',pr,true,'','');
  r := erp_doc_create(mh,'C08','PO',jsonb_build_object('pr',pr,'vendor','NCC04','date','2026-11-03','items','[{"mat":"NV04","qty":20,"price":1230000}]'::jsonb),'',''); po := r->>'id';
  perform erp_doc_decide(ktt,'C08',po,true,'','');
  perform erp_doc_create(kho,'C08','GR',jsonb_build_object('po',po,'date','2026-11-04','dn','PGH2','deliverer','A','items','[{"line":0,"qty":20}]'::jsonb),'','');
  perform pg_temp.t_ok('MIGO linh kiện NV04 ghi Nợ TK 152 = 24.600.000', erp_balance('C08','152') = 24600000, erp_balance('C08','152')::text);

  -- 2. Nhà cung cấp mới: chờ xác nhận; trùng MST bị chặn
  begin perform erp_md_save(mh,'C08','VEN','','{"name":"Công ty trùng","mst":"0312345678"}',''); perform pg_temp.t_ok('XK01: chặn trùng mã số thuế với NCC02', false);
  exception when others then perform pg_temp.t_ok('XK01: chặn trùng mã số thuế với NCC02', sqlerrm like '%đã thuộc nhà cung cấp khác (NCC02)%', sqlerrm); end;
  begin perform erp_md_save(mh,'C08','VEN','','{"name":"MST sai","mst":"12345"}',''); perform pg_temp.t_ok('XK01: kiểm tra định dạng mã số thuế', false);
  exception when others then perform pg_temp.t_ok('XK01: kiểm tra định dạng mã số thuế', true, sqlerrm); end;
  r := erp_md_save(mh,'C08','VEN','','{"name":"Công ty TNHH Thiết bị Mới Nha Trang","mst":"4201779977","bank_acc":"9999 0000 1111","bank_name":"NH Mô phỏng"}',''); vend := r->>'key';
  perform pg_temp.t_ok('XK01: NCC mới NCC07 ở trạng thái chưa xác nhận', vend = 'NCC07' and not (select confirmed from erp_partner where co='C08' and code=vend), vend);
  r := erp_doc_create(kho,'C08','PR','{"date":"2026-11-06","reason":"x","items":[{"mat":"HH04","qty":5}]}','',''); pr := r->>'id';
  perform erp_doc_decide(ktt,'C08',pr,true,'','');
  begin perform erp_doc_create(mh,'C08','PO',jsonb_build_object('pr',pr,'vendor',vend,'date','2026-11-06','items','[{"mat":"HH04","qty":5,"price":290000}]'::jsonb),'','');
    perform pg_temp.t_ok('ME21N: không đặt hàng NCC chưa được KTT xác nhận', false);
  exception when others then perform pg_temp.t_ok('ME21N: không đặt hàng NCC chưa được KTT xác nhận', sqlerrm like '%chưa được Kế toán trưởng xác nhận%', sqlerrm); end;
  select id into chg from erp_md_change where co='C08' and key=vend and field='*tạo mới';
  begin perform erp_md_decide(mh,'C08',chg,true,'',''); perform pg_temp.t_ok('ZMDA: Mua hàng không tự xác nhận NCC mình tạo', false);
  exception when others then perform pg_temp.t_ok('ZMDA: Mua hàng không tự xác nhận NCC mình tạo', true, sqlerrm); end;
  perform erp_md_decide(ktt,'C08',chg,true,'Đã đối chiếu giấy phép kinh doanh','');
  r := erp_doc_create(mh,'C08','PO',jsonb_build_object('pr',pr,'vendor',vend,'date','2026-11-06','items','[{"mat":"HH04","qty":5,"price":290000}]'::jsonb),'','');
  perform pg_temp.t_ok('ME21N: đặt hàng được sau khi KTT xác nhận NCC07', r->>'status' = 'pending');

  -- 3. Đổi tài khoản ngân hàng NCC02: chờ duyệt; F-53 dùng tài khoản cũ đến khi duyệt
  bank0 := (select bank_acc from erp_partner where co='C08' and code='NCC02');
  r := erp_md_save(mh,'C08','VEN','NCC02','{"bank_acc":"6666 7777 8888 99","address":"Số 50 đường Ba Tháng Hai, TP. Hồ Chí Minh"}','');
  perform pg_temp.t_ok('XK02: tài khoản ngân hàng vào trạng thái chờ duyệt, địa chỉ áp dụng ngay',
    (r->'pending') ? 'bank_acc' and (r->'applied') ? 'address' and (select bank_acc from erp_partner where co='C08' and code='NCC02') = bank0, r::text);
  begin perform erp_md_save(mh,'C08','VEN','NCC02','{"bank_acc":"1234"}',''); perform pg_temp.t_ok('XK02: không gửi chồng thay đổi khi đang chờ duyệt', false);
  exception when others then perform pg_temp.t_ok('XK02: không gửi chồng thay đổi khi đang chờ duyệt', sqlerrm like '%đang có một thay đổi chờ duyệt%', sqlerrm); end;
  -- mua – nhập – hóa đơn NCC02 rồi đề nghị chi chuyển khoản
  r := erp_doc_create(kho,'C08','PR','{"date":"2026-11-07","reason":"x","items":[{"mat":"HH05","qty":10}]}','',''); pr := r->>'id';
  perform erp_doc_decide(ktt,'C08',pr,true,'','');
  r := erp_doc_create(mh,'C08','PO',jsonb_build_object('pr',pr,'vendor','NCC02','date','2026-11-07','items','[{"mat":"HH05","qty":10,"price":921500}]'::jsonb),'',''); po := r->>'id';
  perform erp_doc_decide(ktt,'C08',po,true,'','');
  perform erp_doc_create(kho,'C08','GR',jsonb_build_object('po',po,'date','2026-11-08','dn','P3','deliverer','A','items','[{"line":0,"qty":10}]'::jsonb),'','');
  r := erp_doc_create(kt,'C08','IV',jsonb_build_object('po',po,'date','2026-11-08','invSym','1C26THA','invNo','555','items','[{"line":0,"qty":10,"price":921500}]'::jsonb),'',''); iv := r->>'id';
  r := erp_doc_create(kt,'C08','PAY',jsonb_build_object('iv',iv,'date','2026-11-09','acc','112','amount',5000000),'',''); pay := r->>'id';
  perform pg_temp.t_ok('F-53 lập khi thay đổi đang chờ: dùng tài khoản cũ', (select data->>'bankAcc' from erp_doc where co='C08' and id=pay) = bank0);
  select id into chg from erp_md_change where co='C08' and key='NCC02' and field='bank_acc' and status='pending';
  update erp_user set extra = '{MH}' where username = 'tst_ktt';
  begin perform erp_md_decide(ktt,'C08',chg,true,'',''); perform pg_temp.t_ok('ZMDA: KTT duyệt được thay đổi do người khác yêu cầu', true);
  exception when others then perform pg_temp.t_ok('ZMDA: KTT duyệt được thay đổi do người khác yêu cầu', false, sqlerrm); end;
  update erp_user set extra = '{}' where username = 'tst_ktt';
  perform pg_temp.t_ok('ZMDA: sau khi duyệt, dữ liệu gốc NCC02 mang tài khoản mới',
    (select bank_acc from erp_partner where co='C08' and code='NCC02') = '6666 7777 8888 99');
  perform erp_doc_decide(ktt,'C08',pay,true,'','');
  perform pg_temp.t_ok('ZFAP: phiếu chi ghi sổ dùng tài khoản đang hiệu lực lúc duyệt chi',
    (select data->>'bankAcc' from erp_doc where co='C08' and id=pay) = '6666 7777 8888 99');
  -- KTT kiêm MH tự yêu cầu thì không tự duyệt
  update erp_user set extra = '{MH}' where username = 'tst_ktt';
  r := erp_md_save(ktt,'C08','VEN','NCC03','{"terms":60}','');
  select id into chg from erp_md_change where co='C08' and key='NCC03' and field='terms' and status='pending';
  begin perform erp_md_decide(ktt,'C08',chg,true,'',''); perform pg_temp.t_ok('ZMDA: KTT kiêm MH không tự duyệt yêu cầu của chính mình', false);
  exception when others then perform pg_temp.t_ok('ZMDA: KTT kiêm MH không tự duyệt yêu cầu của chính mình', sqlerrm like 'Vi phạm bất kiêm nhiệm%', sqlerrm); end;
  update erp_user set extra = '{}' where username = 'tst_ktt';

  -- 4. Khóa khách hàng → không lập được đơn bán
  r := erp_md_save(kd,'C08','CUS','KH02','{"active":false}','');
  select id into chg from erp_md_change where co='C08' and key='KH02' and field='active' and status='pending';
  perform erp_md_decide(ktt,'C08',chg,true,'Khách nợ quá hạn','');
  begin perform erp_doc_create(kd,'C08','SO','{"cust":"KH02","custPo":"X","date":"2026-11-10","items":[{"mat":"HH01","qty":1,"price":23900000}]}','','');
    perform pg_temp.t_ok('VA01: không bán cho khách đang bị khóa', false);
  exception when others then perform pg_temp.t_ok('VA01: không bán cho khách đang bị khóa', sqlerrm like '%đang bị khóa%', sqlerrm); end;

  -- 5. Quyền theo vai trò: KT = AP + AR; AP không lập hóa đơn bán
  perform pg_temp.t_ok('Vai trò KT được lập MIRO và VF01', erp_can(erp_expand(array['KT']),'MIRO','C') and erp_can(erp_expand(array['KT']),'VF01','C'));
  update erp_user set role = 'AP' where username = 'tst_kt';
  begin perform erp_doc_create(kt,'C08','BI',jsonb_build_object('dl',dl,'date','2026-11-11'),'',''); perform pg_temp.t_ok('AP không lập được hóa đơn bán (SU53)', false);
  exception when others then perform pg_temp.t_ok('AP không lập được hóa đơn bán (SU53)', sqlerrm like '%SU53%', sqlerrm); end;
  update erp_user set role = 'KT' where username = 'tst_kt';
  perform pg_temp.t_ok('Có đủ 15 vai trò và 5 gói vai trò', (select count(*) from erp_role) = 15 and (select count(*) from erp_role_pack) = 5);

  -- 6. Gói vai trò
  insert into erp_session(user_id, expires_at) select id, now() + interval '10 minutes' from erp_user where username = 'gv';
  s := erp_admin_apply_pack((select s.token::text from erp_session s join erp_user u on u.id=s.user_id where u.username='gv' order by expires_at desc limit 1),'PK2','C08');
  perform pg_temp.t_ok('PK2 với 5 người: kd=KHO, kho=MH+KD, kt=AP, ktt=AR, mh=KTT',
    (select role from erp_user where username='tst_kd') = 'KHO' and (select role||coalesce(array_to_string(extra,','),'') from erp_user where username='tst_kho') = 'MHKD'
    and (select role from erp_user where username='tst_ktt') = 'AR' and (select role from erp_user where username='tst_mh') = 'KTT', s::text);
  delete from erp_user where username = 'tst_mh';
  s := erp_admin_apply_pack((select s.token::text from erp_session s join erp_user u on u.id=s.user_id where u.username='gv' order by expires_at desc limit 1),'PK1','C08');
  perform pg_temp.t_ok('PK1 với 4 người: KTT là ghế chính, ghế dư KT ghép vào người ít xung đột (không phải Thủ kho), đủ 5 vai trò',
    (select bool_and(not ('KTT' = any(extra))) from erp_user where co='C08' and not is_admin)
    and (select count(distinct x) from erp_user u, unnest(array[u.role] || u.extra) x where u.co='C08' and not u.is_admin) = 5
    and not exists (select 1 from erp_user where co='C08' and role='KHO' and 'KT' = any(extra)), s::text);

  -- 7. Đồng bộ trả dữ liệu gốc, vai trò, quyền
  s := erp_sync(kho,'*',null);
  perform pg_temp.t_ok('erp_sync: sinh viên nhận dữ liệu gốc đúng công ty mình, đủ vai trò và quyền',
    s->'md' ? 'C08' and not (s->'md' ? 'C01') and jsonb_array_length(s->'auth'->'roles') = 15 and s->'auth'->'perms' ? 'KTT'
    and jsonb_array_length(s->'md'->'C08'->'chg') > 0);
  perform pg_temp.t_ok('anon không đọc được bảng nhật ký thay đổi', not has_table_privilege('anon','erp_md_change','select'));
  perform pg_temp.t_ok('anon không gọi được erp_md_apply (ghi thẳng dữ liệu gốc)', not has_function_privilege('anon','erp_md_apply(text,text,text,text,text)','execute'));

  -- Dọn dẹp
  perform erp_purge_co('C08');
  delete from erp_session where user_id in (select id from erp_user where username like 'tst\_%') or (user_id = (select id from erp_user where username='gv') and expires_at < now() + interval '11 minutes');
  delete from erp_user where username like 'tst\_%';
  delete from erp_md_change where co = 'C08';
  delete from erp_price where co = 'C08' and by is not null;
  delete from erp_mat where co = 'C08' and code not in ('HH01','HH02','HH03','HH04','HH05','NV01','NV02','NV03','NV04','NV05','NV06','TP01','TP02','DV01','DV02');
  delete from erp_partner where co = 'C08' and code not in ('NCC01','NCC02','NCC03','NCC04','NCC05','NCC06','KH01','KH02','KH03','KH04','KH05','KH06');
  update erp_partner set bank_acc = '0071 0012 3456 02', address = 'Số 48 đường Ba Tháng Hai, TP. Hồ Chí Minh', active = true where co = 'C08' and code = 'NCC02';
  update erp_partner set active = true where co = 'C08' and code = 'KH02';
  update erp_partner set terms = 45 where co = 'C08' and code = 'NCC03';
  update erp_cfg set v = cfg0 where k = 'main';
  update erp_co_state set wdate = wd0 where co = 'C08';
end $$;

select n, case when ok then 'ĐẠT' else 'KHÔNG ĐẠT' end kq, name, left(detail,140) detail from tst_p2 order by n;
