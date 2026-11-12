-- =====================================================================
-- Kiểm thử P3b – các phát hiện rà soát độc lập lần 2 (RV2-01 … RV2-09).
-- CHỈ CHẠY TRÊN erp-lab-dev (xóa dữ liệu C08). Chốt an toàn: erp_cfg.main.env = "dev".
-- =====================================================================
create temp table tst_p3b(n serial, name text, ok boolean, detail text);
create function pg_temp.t_ok(p_name text, p_ok boolean, p_detail text default '') returns void language sql as
$$ insert into tst_p3b(name, ok, detail) values (p_name, coalesce(p_ok,false), coalesce(p_detail,'')) $$;
create function pg_temp.t_eq(p_name text, p_got numeric, p_exp numeric) returns void language sql as
$$ select pg_temp.t_ok(p_name, p_got = p_exp, 'được ' || coalesce(p_got::text,'null') || ', kỳ vọng ' || p_exp) $$;

do $$
declare
  cfg0 jsonb; wd0 date; gv text; th text; tq text; ktt text; kt text; kd text; kho text;
  r jsonb; ln text; bsu text; so text; dl text; bi text; clr text; rv text; w1 text; w2 text; adv text; dep text;
begin
  if coalesce((select v->>'env' from erp_cfg where k = 'main'),'') <> 'dev' then
    raise exception 'Kiểm thử chỉ chạy trên cơ sở dữ liệu phát triển (erp_cfg.main.env = "dev"). Dừng để bảo vệ dữ liệu lớp học.';
  end if;
  select v into cfg0 from erp_cfg where k = 'main';
  update erp_cfg set v = v || '{"tol":5,"poAuto":0,"credit":true,"selfApprove":false,"vat":0.08,"bankClear":true}' where k = 'main';
  select wdate into wd0 from erp_co_state where co = 'C08';
  perform erp_purge_co('C08');
  delete from erp_user where username like 'tst\_%';
  insert into erp_user(username, full_name, pass_hash, co, role, must_change) values
    ('tst_th','TH thử','x','C08','TH',false), ('tst_tq','TQ thử','x','C08','TQ',false), ('tst_ktt','KTT thử','x','C08','KTT',false),
    ('tst_kt','KT thử','x','C08','KT',false), ('tst_kd','KD thử','x','C08','KD',false), ('tst_kho','Kho thử','x','C08','KHO',false);
  insert into erp_session(user_id, expires_at) select id, now() + interval '1 hour' from erp_user where username like 'tst\_%' or username = 'gv';
  select s.token::text into gv  from erp_session s join erp_user u on u.id=s.user_id where u.username='gv' order by s.expires_at desc limit 1;
  select s.token::text into th  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_th';
  select s.token::text into tq  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_tq';
  select s.token::text into ktt from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_ktt';
  select s.token::text into kt  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_kt';
  select s.token::text into kd  from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_kd';
  select s.token::text into kho from erp_session s join erp_user u on u.id=s.user_id where u.username='tst_kho';
  perform erp_admin_set_state(gv, 'C08', '{"wdate":"2026-11-10","reseed":true,"cashCount":""}');
  perform erp_admin_set_state(gv, 'C08', '{"wdate":"2026-12-02"}');
  perform erp_bank_issue('C08');

  -- Tiền về chưa rõ 15.000.000 → treo 3388; hóa đơn bán KH01 4.536.000
  select id into ln from erp_bank_line where co='C08' and kind='unk';
  perform erp_bank_match(th,'C08',ln,'{}',''); select bs_doc into bsu from erp_bank_line where co='C08' and id=ln;
  r := erp_doc_create(kd,'C08','SO','{"cust":"KH01","custPo":"RV2","date":"2026-12-02","items":[{"mat":"HH04","qty":10,"price":420000}]}','',''); so := r->>'id';
  r := erp_doc_create(kho,'C08','DL',jsonb_build_object('so',so,'date','2026-12-02','receiver','A','items','[{"line":0,"qty":10}]'::jsonb),'',''); dl := r->>'id';
  r := erp_doc_create(kt,'C08','BI',jsonb_build_object('dl',dl,'date','2026-12-02'),'',''); bi := r->>'id';
  r := erp_susp_clear(th,'C08',bsu,bi,4536000,''); clr := r->>'id';

  -- RV2-01: không đảo khoản treo đã phân bổ
  begin perform erp_doc_create(th,'C08','JE',jsonb_build_object('date','2026-12-02','kind','rev','revOf',bsu,'reason','x'),'','');
    perform pg_temp.t_ok('RV2-01: FB08 không đảo khoản tiền về đã phân bổ cho hóa đơn', false);
  exception when others then perform pg_temp.t_ok('RV2-01: FB08 không đảo khoản tiền về đã phân bổ cho hóa đơn', sqlerrm like 'Khoản tiền về này đã được phân bổ%', sqlerrm); end;

  -- RV2-02: đảo chứng từ phân bổ (có dòng 131 kèm khách hàng) duyệt được
  r := erp_doc_create(th,'C08','JE',jsonb_build_object('date','2026-12-02','kind','rev','revOf',clr,'reason','Phân bổ nhầm khách'),'',''); rv := r->>'id';
  perform pg_temp.t_ok('RV2-02: dòng đảo giữ đối tượng công nợ KH01',
    exists (select 1 from erp_doc d, jsonb_array_elements(d.data->'lines') x where d.co='C08' and d.id=rv and x->>'a'='131' and x->>'p'='KH01'));
  begin perform erp_doc_decide(ktt,'C08',rv,true,'','');
    perform pg_temp.t_ok('RV2-02: KTT duyệt đảo phân bổ → 131 KH01 về 4.536.000, 3388 về −15.000.000',
      erp_balance_p('C08','131','KH01') = 4536000 and erp_balance('C08','3388') = -15000000);
  exception when others then perform pg_temp.t_ok('RV2-02: KTT duyệt đảo phân bổ → 131 KH01 về 4.536.000, 3388 về −15.000.000', false, sqlerrm); end;
  perform pg_temp.t_ok('RV2-02: sau khi đảo, hóa đơn lại còn phải thu đủ (phân bổ cũ không còn tính)', erp_bs_alloc('C08', bi) = 0);

  -- RV2-01 (biến thể): có đề nghị đảo chờ duyệt thì không phân bổ được
  r := erp_doc_create(th,'C08','JE',jsonb_build_object('date','2026-12-02','kind','rev','revOf',bsu,'reason','Ngân hàng ghi nhầm'),'',''); rv := r->>'id';
  begin perform erp_susp_clear(th,'C08',bsu,bi,1000000,''); perform pg_temp.t_ok('RV2-01: không phân bổ khi khoản treo đang có đề nghị FB08 chờ duyệt', false);
  exception when others then perform pg_temp.t_ok('RV2-01: không phân bổ khi khoản treo đang có đề nghị FB08 chờ duyệt', sqlerrm like '%đang có đề nghị đảo%', sqlerrm); end;
  perform erp_doc_decide(ktt,'C08',rv,true,'','');
  perform pg_temp.t_ok('RV2-01: đảo khoản treo chưa phân bổ → 3388 = 0, dòng sao kê mở lại',
    erp_balance('C08','3388') = 0 and (select status from erp_bank_line where co='C08' and id=ln) = 'open');

  -- RV2-06: 3388 bị ghi tay hết thì không phân bổ vượt số dư sổ
  perform erp_bank_match(th,'C08',ln,'{}',''); select bs_doc into bsu from erp_bank_line where co='C08' and id=ln;
  r := erp_doc_create(th,'C08','JE','{"date":"2026-12-02","memo":"Ghi nhầm 3388 sang thu nhập khác","lines":[{"a":"3388","dr":15000000},{"a":"711","cr":15000000}]}','','');
  perform erp_doc_decide(ktt,'C08',r->>'id',true,'','');
  begin perform erp_susp_clear(th,'C08',bsu,bi,1000000,''); perform pg_temp.t_ok('RV2-06: không phân bổ khi số dư Có TK 3388 trên sổ đã hết', false);
  exception when others then perform pg_temp.t_ok('RV2-06: không phân bổ khi số dư Có TK 3388 trên sổ đã hết', sqlerrm like 'Số tiền phân bổ%(0 đồng)%', sqlerrm); end;

  -- RV2-03: rút tiền gửi kiểm tra lại số dư 112 lúc Thủ quỹ xác nhận
  r := erp_doc_create(th,'C08','CJ','{"date":"2026-12-02","dir":"wd","amount":2950000000,"person":"TQ","reason":"Rút lần 1"}','',''); w1 := r->>'id';
  r := erp_doc_create(th,'C08','CJ','{"date":"2026-12-02","dir":"wd","amount":100000000,"person":"TQ","reason":"Rút lần 2"}','',''); w2 := r->>'id';
  perform erp_doc_decide(ktt,'C08',w1,true,'',''); perform erp_doc_decide(ktt,'C08',w2,true,'','');
  perform erp_cash_confirm(tq,'C08',w1,'');
  begin perform erp_cash_confirm(tq,'C08',w2,''); perform pg_temp.t_ok('RV2-03: Thủ quỹ không rút được khi 112 không còn đủ (dù KTT đã duyệt)', false);
  exception when others then perform pg_temp.t_ok('RV2-03: Thủ quỹ không rút được khi 112 không còn đủ (dù KTT đã duyệt)', sqlerrm like 'Không đủ số dư tiền gửi%', sqlerrm); end;
  perform pg_temp.t_ok('RV2-03: TK 112 không âm', erp_balance('C08','112') >= 0, erp_balance('C08','112')::text);

  -- RV2-05: trả lại chứng từ chờ thủ quỹ
  begin perform erp_cash_return(tq,'C08',w2,'',''); perform pg_temp.t_ok('RV2-05: trả lại phải ghi lý do', false);
  exception when others then perform pg_temp.t_ok('RV2-05: trả lại phải ghi lý do', sqlerrm like 'Hãy ghi lý do%', sqlerrm); end;
  begin perform erp_cash_return(kho,'C08',w2,'x',''); perform pg_temp.t_ok('RV2-05: Thủ kho không trả lại được', false);
  exception when others then perform pg_temp.t_ok('RV2-05: Thủ kho không trả lại được', sqlerrm like 'Chỉ Thủ quỹ hoặc Kế toán trưởng%', sqlerrm); end;
  perform erp_cash_return(tq,'C08',w2,'Tài khoản không đủ số dư','');
  perform pg_temp.t_ok('RV2-05: Thủ quỹ trả lại → từ chối, không ghi sổ, có nhật ký "return"',
    (select status = 'rejected' and data->'hist'->-1->>'act' = 'return' and not (data ? 'je') from erp_doc where co='C08' and id=w2));

  -- RV2-04: người đã duyệt không tự chi tiền (KTT kiêm Thủ quỹ)
  update erp_user set extra = '{TQ}' where username = 'tst_ktt';
  r := erp_doc_create(th,'C08','CJ','{"date":"2026-12-02","dir":"out","acc":"6427","cc":"CC700","amount":100000,"person":"A","reason":"VPP"}','','');
  perform erp_doc_decide(ktt,'C08',r->>'id',true,'','');
  begin perform erp_cash_confirm(ktt,'C08',r->>'id','TQ'); perform pg_temp.t_ok('RV2-04: KTT kiêm Thủ quỹ không tự chi phiếu mình đã duyệt', false);
  exception when others then perform pg_temp.t_ok('RV2-04: KTT kiêm Thủ quỹ không tự chi phiếu mình đã duyệt', sqlerrm like '%người đã duyệt%', sqlerrm); end;
  update erp_user set extra = '{}' where username = 'tst_ktt';
  perform erp_cash_return(tq,'C08',r->>'id','Hủy để thử kiểm quỹ','');

  -- RV2-09: còn tạm ứng chờ thủ quỹ chi thì chưa kiểm quỹ
  r := erp_doc_create(kho,'C08','ADV','{"date":"2026-12-02","amount":1000000,"purpose":"Công tác"}','',''); adv := r->>'id';
  perform erp_doc_decide(ktt,'C08',adv,true,'','');
  perform erp_admin_set_state(gv, 'C08', jsonb_build_object('cashCount', erp_balance('C08','111')));
  begin perform erp_doc_create(tq,'C08','CNT','{"date":"2026-12-02","members":"TQ, KTT"}','',''); perform pg_temp.t_ok('RV2-09: còn tạm ứng chờ thủ quỹ chi thì chưa lập biên bản kiểm quỹ', false);
  exception when others then perform pg_temp.t_ok('RV2-09: còn tạm ứng chờ thủ quỹ chi thì chưa lập biên bản kiểm quỹ', sqlerrm like 'Còn chứng từ thu, chi tiền mặt%', sqlerrm); end;
  perform erp_cash_confirm(tq,'C08',adv,'');

  -- RV2-08: tắt TK 113 thì nộp tiền mặt ghi thẳng 112
  update erp_cfg set v = v || '{"bankClear":false}' where k = 'main';
  r := erp_doc_create(th,'C08','CJ','{"date":"2026-12-02","dir":"dep","amount":5000000,"person":"TQ","reason":"Nộp tiền"}','',''); dep := r->>'id';
  perform erp_doc_decide(ktt,'C08',dep,true,'',''); perform erp_cash_confirm(tq,'C08',dep,'');
  perform pg_temp.t_ok('RV2-08: tắt TK 113 → nộp tiền ghi Nợ 112 / Có 111, không qua 113',
    exists (select 1 from erp_je_line l join erp_je j on j.co=l.co and j.id=l.je_id where j.co='C08' and j.doc_id=dep and l.acc='112' and l.dr=5000000)
    and not exists (select 1 from erp_je_line l join erp_je j on j.co=l.co and j.id=l.je_id where j.co='C08' and j.doc_id=dep and l.acc='113'));

  perform pg_temp.t_ok('Mọi bút toán cân Nợ = Có', not exists (select 1 from erp_je_line where co='C08' group by je_id having sum(dr) <> sum(cr)));
  perform pg_temp.t_ok('Bản sao data.je trùng sổ cái (số dòng)',
    (select count(*) from erp_doc d, jsonb_array_elements(d.data->'je') x where d.co='C08' and jsonb_typeof(d.data->'je')='array')
    = (select count(*) from erp_je_line where co='C08'));
  perform pg_temp.t_ok('anon gọi được erp_cash_return (cửa API, có kiểm tra phiên)', has_function_privilege('anon','erp_cash_return(text,text,text,text,text)','execute'));

  perform erp_purge_co('C08');
  delete from erp_session where user_id in (select id from erp_user where username like 'tst\_%') or token::text = gv;
  delete from erp_user where username like 'tst\_%';
  update erp_cfg set v = cfg0 where k = 'main';
  update erp_co_state set wdate = coalesce(wd0, current_date), cash_count = null where co = 'C08';
  perform erp_bank_seed('C08');
end $$;

select n, case when ok then 'ĐẠT' else 'KHÔNG ĐẠT' end kq, name, left(detail,160) detail from tst_p3b order by n;
