-- =====================================================================
-- Kiểm thử P4 – mua hàng và kho nâng cao. CHỈ CHẠY TRÊN erp-lab-dev (xóa dữ liệu C08). Chốt: erp_cfg.main.env = "dev".
-- Kịch bản nghiệm thu: mua 100 HH04 theo báo giá → nhận 100 → trả 4 hàng lỗi (giữ 96) → hóa đơn 96 có phí vận chuyển
-- → ứng trước 30% → trả phần còn lại hưởng chiết khấu 2% (điều khoản 2/10 của NCC01). Bảng kỳ vọng tính tay ở cuối tệp.
-- =====================================================================
create temp table tst_p4(n serial, name text, ok boolean, detail text);
create function pg_temp.t_ok(p_name text, p_ok boolean, p_detail text default '') returns void language sql as
$$ insert into tst_p4(name, ok, detail) values (p_name, coalesce(p_ok,false), coalesce(p_detail,'')) $$;
create function pg_temp.t_eq(p_name text, p_got numeric, p_exp numeric) returns void language sql as
$$ select pg_temp.t_ok(p_name, p_got = p_exp, 'được ' || coalesce(p_got::text,'null') || ', kỳ vọng ' || p_exp) $$;

do $$
declare
  cfg0 jsonb; wd0 date; gv text; kho text; mh text; ap text; ktt text; gd text; r jsonb;
  pr text; rfq text; q1 text; q2 text; q3 text; po text; dp text; rtv text; iv text; pay text; rtv2 text;
  pr2 text; po2 text; pr3 text; po3 text; iv2 text; prun text; pi text; scr text;
  q0 numeric; v0 numeric; b0 numeric; s1003 numeric;
begin
  if coalesce((select v->>'env' from erp_cfg where k = 'main'),'') <> 'dev' then
    raise exception 'Kiểm thử chỉ chạy trên cơ sở dữ liệu phát triển (erp_cfg.main.env = "dev"). Dừng để bảo vệ dữ liệu lớp học.';
  end if;
  select v into cfg0 from erp_cfg where k = 'main';
  update erp_cfg set v = v || '{"tol":5,"poAuto":5000000,"poB":20000000,"grTol":2,"credit":true,"selfApprove":false,"vat":0.08,"bankClear":false}' where k = 'main';
  select wdate into wd0 from erp_co_state where co = 'C08';
  update erp_co_state set wdate = '2026-11-10' where co = 'C08';
  perform erp_purge_co('C08');
  update erp_partner set disc_pct = 2, disc_days = 10, active = true where co = 'C08' and code = 'NCC01';
  delete from erp_user where username like 'tst\_%';
  insert into erp_user(username, full_name, pass_hash, co, role, must_change) values
    ('tst_kho','Thủ kho thử','x','C08','KHO',false), ('tst_mh','Mua hàng thử','x','C08','MH',false),
    ('tst_ap','Kế toán phải trả thử','x','C08','AP',false), ('tst_ktt','KTT thử','x','C08','KTT',false),
    ('tst_gd','Giám đốc thử','x','C08','GD',false);
  insert into erp_session(user_id, expires_at) select id, now() + interval '1 hour' from erp_user where username like 'tst\_%' or username = 'gv';
  select s.token::text into gv  from erp_session s join erp_user u on u.id=s.user_id where u.username='gv' order by s.expires_at desc limit 1;
  select s.token::text into kho from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_kho';
  select s.token::text into mh  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_mh';
  select s.token::text into ap  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_ap';
  select s.token::text into ktt from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_ktt';
  select s.token::text into gd  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_gd';
  select coalesce(qty,0), coalesce(value,0) into q0, v0 from erp_val where co='C08' and mat='HH04';
  b0 := erp_balance('C08','112');

  -- ===== Tìm nguồn: ME41 → ME47 → ME49 → ME21N =====
  r := erp_doc_create(kho,'C08','PR','{"date":"2026-11-10","reason":"Bổ sung chuột không dây","items":[{"mat":"HH04","qty":100}]}','',''); pr := r->>'id';
  perform erp_doc_decide(ktt,'C08',pr,true,'','');
  begin perform erp_doc_create(mh,'C08','RFQ',jsonb_build_object('pr',pr,'date','2026-11-10','vendors','["NCC01","NCC02"]'::jsonb),'','');
    perform pg_temp.t_ok('ME41: phải hỏi giá ít nhất 3 nhà cung cấp', false);
  exception when others then perform pg_temp.t_ok('ME41: phải hỏi giá ít nhất 3 nhà cung cấp', sqlerrm like '%ít nhất 3 nhà cung cấp%', sqlerrm); end;
  r := erp_doc_create(mh,'C08','RFQ',jsonb_build_object('pr',pr,'date','2026-11-10','vendors','["NCC01","NCC02","NCC03"]'::jsonb),'',''); rfq := r->>'id';
  perform pg_temp.t_ok('ME41: yêu cầu báo giá ở trạng thái mở', r->>'status' = 'open');
  begin perform erp_doc_create(mh,'C08','PO',jsonb_build_object('pr',pr,'vendor','NCC01','date','2026-11-10','items','[{"mat":"HH04","qty":100,"price":300000}]'::jsonb),'','');
    perform pg_temp.t_ok('ME21N: đề nghị mua đã hỏi giá thì phải lập đơn từ báo giá', false);
  exception when others then perform pg_temp.t_ok('ME21N: đề nghị mua đã hỏi giá thì phải lập đơn từ báo giá', sqlerrm like '%Chọn một báo giá%', sqlerrm); end;
  r := erp_doc_create(mh,'C08','QT',jsonb_build_object('rfq',rfq,'vendor','NCC01','date','2026-11-10','lead',2,'items','[{"price":300000}]'::jsonb),'',''); q1 := r->>'id';
  r := erp_doc_create(mh,'C08','QT',jsonb_build_object('rfq',rfq,'vendor','NCC02','date','2026-11-10','lead',10,'items','[{"price":290000}]'::jsonb),'',''); q2 := r->>'id';
  r := erp_doc_create(mh,'C08','QT',jsonb_build_object('rfq',rfq,'vendor','NCC03','date','2026-11-10','lead',5,'items','[{"price":310000}]'::jsonb),'',''); q3 := r->>'id';
  begin perform erp_doc_create(mh,'C08','QT',jsonb_build_object('rfq',rfq,'vendor','NCC01','date','2026-11-10','items','[{"price":280000}]'::jsonb),'','');
    perform pg_temp.t_ok('ME47: không nhập hai báo giá của cùng một NCC', false);
  exception when others then perform pg_temp.t_ok('ME47: không nhập hai báo giá của cùng một NCC', sqlerrm like 'Đã nhập báo giá%', sqlerrm); end;
  begin perform erp_doc_create(mh,'C08','PO',jsonb_build_object('pr',pr,'qt',q1,'date','2026-11-10'),'','');
    perform pg_temp.t_ok('ME21N: chọn báo giá không thấp nhất phải ghi lý do', false);
  exception when others then perform pg_temp.t_ok('ME21N: chọn báo giá không thấp nhất phải ghi lý do', sqlerrm like '%không phải giá thấp nhất%', sqlerrm); end;
  r := erp_doc_create(mh,'C08','PO',jsonb_build_object('pr',pr,'qt',q1,'date','2026-11-10','reason','Giao trong 2 ngày, NCC02 giao 10 ngày không kịp mùa tựu trường',
         'items','[{"mat":"HH04","qty":100,"price":1}]'::jsonb),'',''); po := r->>'id';
  perform pg_temp.t_ok('ME21N: đơn mua lấy giá từ báo giá (không lấy giá trình duyệt gửi), ghi cờ không chọn giá thấp nhất',
    (select (data->'items'->0->>'price')::numeric = 300000 and (data->>'notCheapest')::boolean and data->>'vendor' = 'NCC01' from erp_doc where co='C08' and id=po));
  perform pg_temp.t_ok('ME41: yêu cầu báo giá đóng sau khi lập đơn mua', (select status from erp_doc where co='C08' and id=rfq) = 'closed');

  -- ===== Duyệt 2 cấp theo giá trị: 32.400.000 > B = 20.000.000 =====
  perform pg_temp.t_ok('Đơn mua 32.400.000 > hạn mức B: mức duyệt 2', (select (data->>'level')::int from erp_doc where co='C08' and id=po) = 2);
  perform erp_doc_decide(ktt,'C08',po,true,'Đồng ý về giá','');
  perform pg_temp.t_ok('KTT duyệt cấp 1 → chờ Giám đốc', (select status from erp_doc where co='C08' and id=po) = 'pending2');
  begin perform erp_doc_decide(ktt,'C08',po,true,'',''); perform pg_temp.t_ok('KTT không duyệt được cấp 2', false);
  exception when others then perform pg_temp.t_ok('KTT không duyệt được cấp 2', sqlerrm like '%cần Giám đốc%', sqlerrm); end;
  perform erp_doc_decide(gd,'C08',po,true,'','');
  perform pg_temp.t_ok('Giám đốc duyệt cấp 2 → đơn mua đã duyệt', (select status = 'approved' and data->>'dec2By' is not null from erp_doc where co='C08' and id=po));

  -- ===== F-48 ứng trước 30% =====
  begin perform erp_doc_create(ap,'C08','PAY',jsonb_build_object('po',po,'date','2026-11-10','acc','112','amount',33000000),'','');
    perform pg_temp.t_ok('F-48: không ứng trước vượt giá trị đơn mua', false);
  exception when others then perform pg_temp.t_ok('F-48: không ứng trước vượt giá trị đơn mua', sqlerrm like 'Số tiền ứng trước không hợp lệ%', sqlerrm); end;
  r := erp_doc_create(ap,'C08','PAY',jsonb_build_object('po',po,'date','2026-11-10','acc','112','amount',9720000,'kind','dp','disc',5000000),'',''); dp := r->>'id';
  perform pg_temp.t_ok('F-48: trình duyệt không tự gán chiết khấu (trường disc bị bỏ)', (select coalesce((data->>'disc')::numeric,0) = 0 and data->>'kind' = 'dp' from erp_doc where co='C08' and id=dp));
  perform erp_doc_decide(ktt,'C08',dp,true,'','');
  perform pg_temp.t_eq('F-48: ứng trước ghi Nợ 331 NCC01 = 9.720.000', erp_balance_p('C08','331','NCC01'), 9720000);

  -- ===== MIGO 101 có dung sai 2%, 122 trả hàng =====
  begin perform erp_doc_create(kho,'C08','GR',jsonb_build_object('po',po,'date','2026-11-10','dn','PGH-77','deliverer','A','items','[{"line":0,"qty":103}]'::jsonb),'','');
    perform pg_temp.t_ok('MIGO 101: nhận vượt dung sai 2% (103/100) bị chặn', false);
  exception when others then perform pg_temp.t_ok('MIGO 101: nhận vượt dung sai 2% (103/100) bị chặn', sqlerrm like 'Nhập vượt đơn mua%', sqlerrm); end;
  perform erp_doc_create(kho,'C08','GR',jsonb_build_object('po',po,'date','2026-11-10','dn','PGH-77','deliverer','Anh Bình','items','[{"line":0,"qty":100}]'::jsonb),'','');
  r := erp_doc_create(kho,'C08','RTV',jsonb_build_object('po',po,'date','2026-11-10','reason','4 chuột lỗi cảm biến, biên bản BB-12','items','[{"line":0,"qty":4}]'::jsonb),'',''); rtv := r->>'id';
  perform pg_temp.t_ok('MIGO 122: trả 4 hàng lỗi → Nợ 331 / Có 156 = 1.200.000, chưa có hóa đơn nên không cần giấy báo có',
    (select (data->>'value')::numeric = 1200000 and (data->'items'->0->>'cmQty')::numeric = 0 from erp_doc where co='C08' and id=rtv));

  -- ===== MIRO 96 có phí vận chuyển, tự bù trừ ứng trước =====
  begin perform erp_doc_create(ap,'C08','IV',jsonb_build_object('po',po,'date','2026-11-10','invSym','1C26TSM','invNo','1001','items','[{"line":0,"qty":97,"price":300000}]'::jsonb),'','');
    perform pg_temp.t_ok('MIRO: không lập hóa đơn cho số đã trả lại (nhận thuần 96)', false);
  exception when others then perform pg_temp.t_ok('MIRO: không lập hóa đơn cho số đã trả lại (nhận thuần 96)', sqlerrm like 'Số lượng hóa đơn vượt số đã nhận thuần%', sqlerrm); end;
  begin perform erp_doc_create(ap,'C08','IV',jsonb_build_object('po',po,'date','2026-11-10','invSym','1C26TSM','invNo','1001','items','[{"line":0,"qty":96,"price":300000,"tax":7}]'::jsonb),'','');
    perform pg_temp.t_ok('MIRO: thuế suất ngoài danh mục (7%) bị chặn', false);
  exception when others then perform pg_temp.t_ok('MIRO: thuế suất ngoài danh mục (7%) bị chặn', sqlerrm like 'Thuế suất%không hợp lệ%', sqlerrm); end;
  r := erp_doc_create(ap,'C08','IV',jsonb_build_object('po',po,'date','2026-11-10','invSym','1C26TSM','invNo','1001','freight',960000,'freightTax',8,
         'gross',32140800,'items','[{"line":0,"qty":96,"price":300000,"tax":8}]'::jsonb),'',''); iv := r->>'id';
  perform pg_temp.t_ok('MIRO: hóa đơn 96 × 300.000 + vận chuyển 960.000, thuế 8% → tổng 32.140.800, bù trừ ứng trước 9.720.000',
    r->>'status' = 'posted' and (select (data->>'total')::numeric = 32140800 and (data->>'dpAlloc')::numeric = 9720000 and data->>'discUntil' = '2026-11-20'
      from erp_doc where co='C08' and id=iv), r::text);
  begin perform erp_doc_create(ap,'C08','IV',jsonb_build_object('po',po,'date','2026-11-10','invSym','1c26tsm','invNo','0001001','items','[{"line":0,"qty":1,"price":300000}]'::jsonb),'','');
    perform pg_temp.t_ok('MIRO: chặn hóa đơn trùng ký hiệu, số theo MST người bán', false);
  exception when others then perform pg_temp.t_ok('MIRO: chặn hóa đơn trùng ký hiệu, số theo MST người bán', sqlerrm like 'Hóa đơn trùng%', sqlerrm); end;

  -- ===== F-53 trả phần còn lại, hưởng chiết khấu 2% =====
  r := erp_doc_create(ap,'C08','PAY',jsonb_build_object('iv',iv,'date','2026-11-10','acc','112','useDisc',true),'',''); pay := r->>'id';
  perform pg_temp.t_ok('F-53: còn phải trả 22.420.800, chiết khấu 2% = 448.416, chi 21.972.384',
    (select (data->>'amount')::numeric = 21972384 and (data->>'disc')::numeric = 448416 and (data->>'settle')::numeric = 22420800 from erp_doc where co='C08' and id=pay));
  perform erp_doc_decide(ktt,'C08',pay,true,'','');

  -- ===== Bảng kỳ vọng nghiệm thu =====
  perform pg_temp.t_eq('NGHIỆM THU: phải trả NCC01 = 0', erp_balance_p('C08','331','NCC01'), 0);
  perform pg_temp.t_eq('NGHIỆM THU: thuế GTGT được khấu trừ 1331 = 2.380.800', erp_balance('C08','1331'), 2380800);
  perform pg_temp.t_eq('NGHIỆM THU: kho HH04 tăng 96 cái', (select qty from erp_val where co='C08' and mat='HH04') - q0, 96);
  perform pg_temp.t_eq('NGHIỆM THU: giá trị kho HH04 tăng 29.760.000 (28.800.000 + vận chuyển 960.000)', (select value from erp_val where co='C08' and mat='HH04') - v0, 29760000);
  perform pg_temp.t_eq('NGHIỆM THU: tiền gửi 112 giảm 31.692.384 (ứng 9.720.000 + chi 21.972.384)', b0 - erp_balance('C08','112'), 31692384);
  perform pg_temp.t_eq('NGHIỆM THU: chiết khấu thanh toán được hưởng ghi Có 515 = 448.416', erp_balance('C08','515'), -448416);
  perform pg_temp.t_ok('NGHIỆM THU: sổ kho bằng sổ cái TK 156', (select sum(value) from erp_val where co='C08' and mat in (select code from erp_mat where co='C08' and acc='156')) = erp_balance('C08','156'));

  -- ===== Trả lại hàng đã có hóa đơn → giấy báo có của NCC =====
  r := erp_doc_create(kho,'C08','RTV',jsonb_build_object('po',po,'date','2026-11-10','reason','2 chuột hỏng phát hiện khi bán','items','[{"line":0,"qty":2}]'::jsonb),'',''); rtv2 := r->>'id';
  perform pg_temp.t_ok('MIGO 122 sau hóa đơn: 2 cái cần giấy báo có', (select (data->'items'->0->>'cmQty')::numeric from erp_doc where co='C08' and id=rtv2) = 2);
  perform erp_doc_create(ap,'C08','CM',jsonb_build_object('rtv',rtv2,'date','2026-11-10','invSym','1C26TSM','invNo','1050'),'','');
  perform pg_temp.t_ok('Giấy báo có: Nợ 331 / Có 1331 thuế 48.000; phải trả NCC01 dư Nợ 648.000 (NCC nợ lại)',
    erp_balance('C08','1331') = 2380800 - 48000 and erp_balance_p('C08','331','NCC01') = 648000);
  begin perform erp_doc_create(ap,'C08','CM',jsonb_build_object('rtv',rtv,'date','2026-11-10','invSym','1C26TSM','invNo','1051'),'','');
    perform pg_temp.t_ok('Giấy báo có: không lập cho hàng trả lại chưa có hóa đơn', false);
  exception when others then perform pg_temp.t_ok('Giấy báo có: không lập cho hàng trả lại chưa có hóa đơn', sqlerrm like '%không cần giấy báo có%', sqlerrm); end;

  -- ===== MIGO 311, 201, 551 =====
  s1003 := erp_sloc_qty('C08','HH04',(select sloc from erp_mat where co='C08' and code='HH04'));
  perform erp_doc_create(kho,'C08','TRF',jsonb_build_object('date','2026-11-10','items',jsonb_build_array(jsonb_build_object('mat','HH04','qty',5,
            'from',(select sloc from erp_mat where co='C08' and code='HH04'),'to','1001'))),'','');
  perform pg_temp.t_ok('MIGO 311: chuyển 5 cái sang kho 1001, không phát sinh bút toán',
    erp_sloc_qty('C08','HH04','1001') = 5 and erp_sloc_qty('C08','HH04',(select sloc from erp_mat where co='C08' and code='HH04')) = s1003 - 5);
  begin perform erp_doc_create(kho,'C08','TRF',jsonb_build_object('date','2026-11-10','items','[{"mat":"HH04","qty":6,"from":"1001","to":"1002"}]'::jsonb),'','');
    perform pg_temp.t_ok('MIGO 311: không chuyển quá tồn của kho đi', false);
  exception when others then perform pg_temp.t_ok('MIGO 311: không chuyển quá tồn của kho đi', sqlerrm like 'Kho 1001 chỉ còn%', sqlerrm); end;
  begin perform erp_doc_create(kho,'C08','GI',jsonb_build_object('date','2026-11-10','reason','Cấp chuột cho phòng kế toán','acc','6428','items','[{"mat":"HH04","qty":1}]'::jsonb),'','');
    perform pg_temp.t_ok('MIGO 201: thiếu trung tâm chi phí bị chặn', false);
  exception when others then perform pg_temp.t_ok('MIGO 201: thiếu trung tâm chi phí bị chặn', true, sqlerrm); end;
  r := erp_doc_create(kho,'C08','GI',jsonb_build_object('date','2026-11-10','reason','Cấp chuột cho phòng kế toán','acc','6428','cc','CC700','items','[{"mat":"HH04","qty":1}]'::jsonb),'','');
  perform pg_temp.t_ok('MIGO 201: xuất dùng ghi Nợ 6428 (CC700) / Có 156 theo giá bình quân', r->>'status' = 'posted'
    and exists (select 1 from erp_je_line l join erp_je j on j.co=l.co and j.id=l.je_id where j.co='C08' and j.doc_id=r->>'id' and l.acc='6428' and l.cc='CC700' and l.dr > 0));
  r := erp_doc_create(kho,'C08','SCR',jsonb_build_object('date','2026-11-10','reason','1 chuột vỡ do rơi kệ','items','[{"mat":"HH04","qty":1}]'::jsonb),'',''); scr := r->>'id';
  perform pg_temp.t_ok('MIGO 551: hủy hàng chờ KTT duyệt, chưa ghi sổ', r->>'status' = 'pending' and not exists (select 1 from erp_je where co='C08' and doc_id=scr));
  perform erp_doc_decide(ktt,'C08',scr,true,'','');
  perform pg_temp.t_ok('MIGO 551: KTT duyệt → Nợ 632 / Có 156', exists (select 1 from erp_je_line l join erp_je j on j.co=l.co and j.id=l.je_id where j.co='C08' and j.doc_id=scr and l.acc='632' and l.dr > 0));

  -- ===== Cảnh báo chia nhỏ đơn: hạn mức A = 5.000.000 =====
  r := erp_doc_create(kho,'C08','PR','{"date":"2026-11-10","reason":"Bàn phím","items":[{"mat":"HH05","qty":3}]}','',''); pr2 := r->>'id';
  perform erp_doc_decide(ktt,'C08',pr2,true,'','');
  r := erp_doc_create(kho,'C08','PR','{"date":"2026-11-10","reason":"Bàn phím đợt 2","items":[{"mat":"HH05","qty":3}]}','',''); pr3 := r->>'id';
  perform erp_doc_decide(ktt,'C08',pr3,true,'','');
  r := erp_doc_create(mh,'C08','PO',jsonb_build_object('pr',pr2,'vendor','NCC02','date','2026-11-10','items','[{"mat":"HH05","qty":3,"price":950000}]'::jsonb),'',''); po2 := r->>'id';
  perform pg_temp.t_ok('Đơn 3.078.000 ≤ A: tự duyệt', r->>'status' = 'approved');
  r := erp_doc_create(mh,'C08','PO',jsonb_build_object('pr',pr3,'vendor','NCC02','date','2026-11-10','items','[{"mat":"HH05","qty":3,"price":950000}]'::jsonb),'',''); po3 := r->>'id';
  perform pg_temp.t_ok('Đơn thứ hai cùng NCC trong 3 ngày, tổng 6.156.000 > A: cảnh báo chia nhỏ và không tự duyệt',
    r->>'status' = 'pending' and (select data ? 'splitWarn' from erp_doc where co='C08' and id=po3));

  -- ===== F110 đợt thanh toán =====
  perform erp_doc_create(kho,'C08','GR',jsonb_build_object('po',po2,'date','2026-11-10','dn','PG-88','deliverer','B','items','[{"line":0,"qty":3}]'::jsonb),'','');
  r := erp_doc_create(ap,'C08','IV',jsonb_build_object('po',po2,'date','2026-11-10','invSym','1C26THA','invNo','777','items','[{"line":0,"qty":3,"price":950000}]'::jsonb),'',''); iv2 := r->>'id';
  r := erp_doc_create(ap,'C08','PRUN',jsonb_build_object('date','2026-11-10','dueBy','2026-12-31','items',jsonb_build_array(jsonb_build_object('iv',iv2))),'',''); prun := r->>'id';
  perform pg_temp.t_ok('F110: đề xuất đợt 3.078.000 chờ KTT duyệt', r->>'status' = 'pending' and (select (data->>'amount')::numeric from erp_doc where co='C08' and id=prun) = 3078000);
  perform erp_doc_decide(ktt,'C08',prun,true,'','');
  perform pg_temp.t_ok('F110: KTT duyệt → sinh phiếu chi chuyển khoản, phải trả NCC02 = 0',
    (select status = 'posted' and jsonb_array_length(data->'pays') = 1 from erp_doc where co='C08' and id=prun) and erp_balance_p('C08','331','NCC02') = 0);

  -- ===== MI01 / MI04 / MI07 kiểm kê =====
  r := erp_doc_create(kho,'C08','PI',jsonb_build_object('date','2026-11-10','mats','["HH04"]'::jsonb,'members','Thủ kho, KSNB'),'',''); pi := r->>'id';
  begin perform erp_doc_create(kho,'C08','GI',jsonb_build_object('date','2026-11-10','reason','Cấp thêm 1 chuột','acc','6428','cc','CC700','items','[{"mat":"HH04","qty":1}]'::jsonb),'','');
    perform pg_temp.t_ok('MI01: vật tư đang kiểm kê bị đóng băng, không xuất được', false);
  exception when others then perform pg_temp.t_ok('MI01: vật tư đang kiểm kê bị đóng băng, không xuất được', sqlerrm like '%đang kiểm kê%', sqlerrm); end;
  begin perform erp_pi_count(kho,'C08',pi,'{"HH04":1}'); perform pg_temp.t_ok('MI04: chỉ giảng viên nhập số đếm thực tế', false);
  exception when others then perform pg_temp.t_ok('MI04: chỉ giảng viên nhập số đếm thực tế', sqlerrm like 'Chỉ giảng viên%', sqlerrm); end;
  perform erp_pi_count(gv,'C08',pi,jsonb_build_object('HH04',(select qty from erp_val where co='C08' and mat='HH04') - 2));
  begin perform erp_pi_submit(kho,'C08',pi,'',''); perform pg_temp.t_ok('MI07: có chênh lệch phải ghi nguyên nhân', false);
  exception when others then perform pg_temp.t_ok('MI07: có chênh lệch phải ghi nguyên nhân', sqlerrm like 'Có chênh lệch%', sqlerrm); end;
  perform erp_pi_submit(kho,'C08',pi,'Thiếu 2 cái, nghi xuất bán chưa lập phiếu','');
  q0 := (select value from erp_val where co='C08' and mat='HH04') / (select qty from erp_val where co='C08' and mat='HH04') * 2;
  perform erp_doc_decide(ktt,'C08',pi,true,'Lập biên bản, truy trách nhiệm','');
  perform pg_temp.t_ok('MI07: thiếu 2 cái → Nợ 1381 / Có 156 theo giá bình quân; hết đóng băng',
    erp_balance('C08','1381') = round(q0) and not erp_pi_frozen('C08','HH04'), erp_balance('C08','1381')::text || ' / ' || round(q0));

  -- ===== Bất biến =====
  perform pg_temp.t_ok('Mọi bút toán cân Nợ = Có', not exists (select 1 from erp_je_line where co='C08' group by je_id having sum(dr) <> sum(cr)));
  perform pg_temp.t_ok('Sổ kho bằng sổ cái TK 156 sau mọi loại di chuyển', (select sum(value) from erp_val where co='C08' and mat in (select code from erp_mat where co='C08' and acc='156')) = erp_balance('C08','156'));
  perform pg_temp.t_ok('Số lượng tồn theo kho cộng lại bằng tồn sổ (HH04)',
    (select sum(erp_sloc_qty('C08','HH04',code)) from erp_org where co='C08' and kind='SLOC') = (select qty from erp_val where co='C08' and mat='HH04'));
  perform pg_temp.t_ok('Bản sao data.je trùng sổ cái (số dòng)',
    (select count(*) from erp_doc d, jsonb_array_elements(d.data->'je') x where d.co='C08' and jsonb_typeof(d.data->'je')='array')
    = (select count(*) from erp_je_line where co='C08'));
  perform pg_temp.t_ok('anon không gọi được erp_mm_create, erp_val_out', not has_function_privilege('anon','erp_mm_create(erp_user,text,text[],text,text,jsonb,text,date)','execute')
    and not has_function_privilege('anon','erp_val_out(text,text,numeric)','execute'));

  perform erp_purge_co('C08');
  delete from erp_session where user_id in (select id from erp_user where username like 'tst\_%') or token::text = gv;
  delete from erp_user where username like 'tst\_%';
  update erp_cfg set v = cfg0 where k = 'main';
  update erp_co_state set wdate = coalesce(wd0, current_date) where co = 'C08';
end $$;

select n, case when ok then 'ĐẠT' else 'KHÔNG ĐẠT' end kq, name, left(detail,160) detail from tst_p4 order by n;
-- BẢNG KỲ VỌNG (tính tay)
-- Đơn mua: 100 × 300.000 = 30.000.000; thuế 8% 2.400.000; tổng 32.400.000 → mức 2 (B = 20.000.000)
-- Ứng trước 30%: 9.720.000 (Nợ 331 / Có 112)
-- Nhập 100: Nợ 156 30.000.000 / Có 331 30.000.000; trả 4: Nợ 331 1.200.000 / Có 156 1.200.000
-- Hóa đơn 96: tiền hàng 28.800.000 + vận chuyển 960.000; thuế 2.304.000 + 76.800 = 2.380.800; tổng 32.140.800
--   Nợ 156 960.000 (phân bổ vận chuyển), Nợ 1331 2.380.800 / Có 331 3.340.800; bù trừ ứng trước 9.720.000
-- Còn phải trả 32.140.800 − 9.720.000 = 22.420.800; chiết khấu 2% = 448.416; chi 21.972.384
--   Nợ 331 22.420.800 / Có 112 21.972.384 / Có 515 448.416
-- Số dư 331 NCC01: −30.000.000 + 1.200.000 − 3.340.800 + 9.720.000 + 22.420.800 = 0
-- Kho HH04: +96 cái, +29.760.000; 112 giảm 31.692.384
