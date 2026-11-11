-- =====================================================================
-- ERP Lab 2.0 – P3: sổ cái, kỳ kế toán, tiền và ngân hàng (SPEC mục 5, 10)
-- Ngày làm việc từng công ty; đóng/mở kỳ theo nhóm tài khoản (OB52); bút toán tay FB50 qua duyệt,
-- đảo FB08, trích trước tự đảo FBS1; quỹ tiền mặt FBCJ, kiểm quỹ; ngân hàng qua TK 113, sao kê FF67,
-- đối chiếu ngân hàng; tạm ứng – hoàn ứng.
-- Các hàm erp_doc_create, erp_doc_decide, erp_md_json, erp_md_changed, erp_sync được định nghĩa tại đây (thay bản 004).
-- Chạy lại nhiều lần vẫn an toàn.
-- =====================================================================

-- ---------- Bảng ----------
alter table erp_je_line add column if not exists cc text;
create table if not exists erp_co_state(
  co text primary key, wdate date not null default current_date, cash_count numeric,
  updated_at timestamptz not null default clock_timestamp()
);
insert into erp_co_state(co) select unnest(erp_cos()) on conflict do nothing;
create table if not exists erp_period_close(
  co text not null, fy int not null, period int not null, grp text not null check (grp in ('+','MM','AR','AP','AA','GL')),
  by uuid, at timestamptz not null default clock_timestamp(),
  primary key(co, fy, period, grp)
);
create table if not exists erp_period_log(
  id bigserial primary key, co text not null, fy int not null, period int not null, grp text not null,
  act text not null, by uuid, at timestamptz not null default clock_timestamp()
);
create table if not exists erp_bank_preset(
  co text not null, id int not null, vdate date not null, kind text not null check (kind in ('fee','int','unk')),
  amt numeric not null, descr text not null, issued boolean not null default false,
  primary key(co, id)
);
create table if not exists erp_bank_line(
  co text not null, id text not null, vdate date not null, amt numeric not null, descr text not null,
  kind text not null check (kind in ('doc','fee','int','unk')), ref_doc text, preset int,
  status text not null default 'open' check (status in ('open','matched')),
  bs_doc text, matched_by uuid, matched_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  primary key(co, id)
);
create unique index if not exists erp_bank_line_ref on erp_bank_line(co, ref_doc) where ref_doc is not null;
alter table erp_co_state enable row level security;
alter table erp_period_close enable row level security;
alter table erp_period_log enable row level security;
alter table erp_bank_preset enable row level security;
alter table erp_bank_line enable row level security;
do $$ begin
  if exists (select 1 from pg_roles where rolname='anon') then
    execute 'revoke all on erp_co_state, erp_period_close, erp_period_log, erp_bank_preset, erp_bank_line from anon';
    execute 'revoke all on sequence erp_period_log_id_seq from anon'; end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then
    execute 'revoke all on erp_co_state, erp_period_close, erp_period_log, erp_bank_preset, erp_bank_line from authenticated';
    execute 'revoke all on sequence erp_period_log_id_seq from authenticated'; end if;
end $$;

-- Xác định tài khoản bổ sung
insert into erp_acct_det(k,acc,note) values
 ('BANK_CLR','113','Tiền đang chuyển – chi/thu qua ngân hàng chờ sao kê'),
 ('CASH_SHORT','1381','Tiền mặt thiếu khi kiểm quỹ, chờ xử lý'),
 ('CASH_OVER','3381','Tiền mặt thừa khi kiểm quỹ, chờ giải quyết'),
 ('BANK_FEE','6427','Phí dịch vụ ngân hàng'),
 ('INT_INC','515','Lãi tiền gửi'),
 ('SUSPENSE','3388','Tiền về chưa rõ nội dung'),
 ('ADV','141','Tạm ứng nhân viên')
on conflict (k) do update set acc = excluded.acc, note = excluded.note;
-- Ngân hàng qua TK 113 (mặc định bật). Tắt để chạy như bản P1 (ghi thẳng 112).
update erp_cfg set v = v || '{"bankClear":true}'::jsonb where k = 'main' and not (v ? 'bankClear');

-- Vai trò, quyền P3
insert into erp_role_perm(role,tc,act)
select r, tc, a from (values
 ('TH','FB50','C'),('TH','FB08','C'),('TH','FBS1','C'),('TH','FF67','C'),('TH','FAGLL03','V'),('TH','ZBRR','V'),('TH','ZSO','V'),
 ('TQ','FBCJ','V'),('TQ','ZTQ','C'),('TQ','ZKQ','C'),('TQ','FAGLL03','V'),
 ('TH','FBCJ','C'),('AP','FBCJ','C'),('AR','FBCJ','C'),
 ('KTT','FBCJ','V'),('KTT','ZKQ','V'),('KTT','FF67','V'),('KTT','ZTU','V'),('GD','FBCJ','V'),('GD','FF67','V'),('KSNB','FBCJ','V'),('KSNB','ZKQ','V'),('KSNB','FF67','V'),('KSNB','ZTU','V'),
 ('KTT','OB52','A'),('KTT','FAGLL03','V'),('KTT','ZBRR','V'),('KTT','ZSO','V'),
 ('GD','FAGLL03','V'),('GD','ZBRR','V'),('GD','ZSO','V'),
 ('KSNB','FAGLL03','V'),('KSNB','ZBRR','V'),('KSNB','ZSO','V'),
 ('AP','FAGLL03','V'),('AR','FAGLL03','V'),('GT','FAGLL03','V'),('TS','FAGLL03','V'),('TQ','ZSO','V')
) as p(r,tc,a) on conflict do nothing;
-- Sau rà soát độc lập (RV-11): Thủ quỹ không lập phiếu, chỉ xác nhận đã thu/đã chi (ZTQ)
update erp_role_perm set act = 'V' where role = 'TQ' and tc = 'FBCJ' and act = 'C'
  and not exists (select 1 from erp_role_perm where role = 'TQ' and tc = 'FBCJ' and act = 'V');
-- Đề nghị tạm ứng / quyết toán: mọi vai trò tác nghiệp (trừ KTT là người duyệt, KSNB độc lập)
insert into erp_role_perm(role,tc,act)
select code, 'ZTU', 'C' from erp_role where code not in ('KTT','KSNB') on conflict do nothing;

-- ---------- Tiện ích ----------
create or replace function erp_wdate(p_co text) returns date language sql stable set search_path = public, extensions as
$$ select coalesce((select wdate from erp_co_state where co = p_co), current_date) $$;
create or replace function erp_acct_grp(p_recon text) returns text language sql immutable set search_path = public, extensions as
$$ select case p_recon when 'INV' then 'MM' when 'AR' then 'AR' when 'AP' then 'AP' when 'FA' then 'AA' else 'GL' end $$;
create or replace function erp_period_closed(p_co text, p_date date, p_grp text) returns boolean language sql stable set search_path = public, extensions as
$$ select exists (select 1 from erp_period_close where co = p_co and fy = extract(year from p_date) and period = extract(month from p_date)
                  and grp in ('+', p_grp)) $$;
create or replace function erp_type_role(p_type text) returns text language sql immutable set search_path = public, extensions as $$
  select case p_type when 'PR' then 'KHO' when 'GR' then 'KHO' when 'DL' then 'KHO' when 'PO' then 'MH' when 'SO' then 'KD'
                     when 'IV' then 'AP' when 'PAY' then 'AP' when 'BI' then 'AR' when 'RC' then 'AR'
                     when 'JE' then 'TH' when 'CJ' then 'TH' when 'CNT' then 'TQ' end
$$;
create or replace function erp_type_tc(p_type text) returns text language sql immutable set search_path = public, extensions as $$
  select case p_type when 'PR' then 'ME51N' when 'PO' then 'ME21N' when 'GR' then 'MIGO' when 'IV' then 'MIRO' when 'PAY' then 'F-53'
                     when 'SO' then 'VA01' when 'DL' then 'VL01N' when 'BI' then 'VF01' when 'RC' then 'F-28'
                     when 'JE' then 'FB50' when 'CJ' then 'FBCJ' when 'CNT' then 'ZKQ' when 'ADV' then 'ZTU' when 'ADS' then 'ZTU' end
$$;

-- ---------- Cửa duy nhất tạo bút toán (thay bản P1) ----------
-- Ngày ghi sổ = ngày làm việc của công ty, trừ chứng từ mở sổ (OB) và bút toán tự đảo đầu kỳ sau (đặt erp.fixed_date).
-- Chặn ghi vào kỳ đã đóng theo nhóm tài khoản; bắt buộc trung tâm chi phí; TK tạm ứng 141 phải ghi người nhận tạm ứng.
create or replace function erp_post(p_co text, p_doc_id text, p_doc_type text, p_date date, p_by uuid,
                                    p_lines jsonb, p_memo text default '') returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare l jsonb; a erp_acct; s int; v_id text; n int := 0; tdr numeric := 0; tcr numeric := 0;
        dr numeric; cr numeric; outl jsonb := '[]'; v_date date; y int; per int; g text;
begin
  if jsonb_typeof(p_lines) <> 'array' then raise exception 'Bút toán không hợp lệ.'; end if;
  v_date := case when p_doc_type = 'OB' or coalesce(current_setting('erp.fixed_date', true), '') = 'on'
                 then coalesce(p_date, erp_wdate(p_co)) else erp_wdate(p_co) end;
  y := extract(year from v_date); per := extract(month from v_date);
  perform pg_advisory_xact_lock(hashtext('erp:je:' || p_co));
  select coalesce(max(substr(id, 7)::int), 0) + 1 into s from erp_je where co = p_co and fy = y;
  v_id := 'JE' || y || lpad(s::text, 6, '0');
  insert into erp_je(co,id,doc_id,doc_type,post_date,fy,period,created_by,memo)
  values (p_co, v_id, p_doc_id, p_doc_type, v_date, y, per, p_by, coalesce(p_memo,''));
  for l in select * from jsonb_array_elements(p_lines) loop
    dr := round(coalesce(erp_num(l,'dr'),0)); cr := round(coalesce(erp_num(l,'cr'),0));
    if dr < 0 then cr := cr - dr; dr := 0; end if;
    if cr < 0 then dr := dr - cr; cr := 0; end if;
    if dr = 0 and cr = 0 then continue; end if;
    if dr > 0 and cr > 0 then
      if dr >= cr then dr := dr - cr; cr := 0; else cr := cr - dr; dr := 0; end if;
      if dr = 0 and cr = 0 then continue; end if;
    end if;
    select * into a from erp_acct where code = l->>'a' and active;
    if not found then raise exception 'Tài khoản % không có trong hệ thống tài khoản.', l->>'a'; end if;
    g := erp_acct_grp(a.recon);
    if p_doc_type <> 'OB' and erp_period_closed(p_co, v_date, g) then
      raise exception 'Kỳ %/% đã đóng (nhóm %, TK %). Ghi vào kỳ đang mở hoặc nhờ Kế toán trưởng mở kỳ (OB52).', lpad(per::text,2,'0'), y, g, a.code;
    end if;
    if a.recon in ('AR','AP') and not exists (select 1 from erp_partner where co = p_co and code = l->>'p'
          and kind = case a.recon when 'AR' then 'C' else 'V' end) then
      raise exception 'Dòng ghi TK % thiếu đối tượng công nợ hợp lệ.', a.code;
    end if;
    if a.recon = 'ADV' and not exists (select 1 from erp_user where username = l->>'p') then
      raise exception 'Dòng ghi TK % thiếu người nhận tạm ứng.', a.code;
    end if;
    if a.recon = 'INV' and not exists (select 1 from erp_mat where co = p_co and code = l->>'mat') then
      raise exception 'Dòng ghi TK % thiếu mã vật tư hợp lệ.', a.code;
    end if;
    if a.cc_req and not exists (select 1 from erp_org where co = p_co and kind = 'CC' and code = l->>'cc') then
      raise exception 'TK % bắt buộc ghi trung tâm chi phí (CC100–CC700).', a.code;
    end if;
    n := n + 1;
    insert into erp_je_line(co,je_id,ln,acc,dr,cr,partner,mat,qty,memo,cc)
    values (p_co, v_id, n, a.code, dr, cr, nullif(l->>'p',''), nullif(l->>'mat',''), erp_num(l,'q'), coalesce(l->>'memo',''), nullif(l->>'cc',''));
    tdr := tdr + dr; tcr := tcr + cr;
    outl := outl || jsonb_strip_nulls(jsonb_build_object('a',a.code,'dr',nullif(dr,0),'cr',nullif(cr,0),
              'p',nullif(l->>'p',''),'mat',nullif(l->>'mat',''),'q',erp_num(l,'q'),'cc',nullif(l->>'cc',''),'memo',nullif(l->>'memo','')));
  end loop;
  if n < 2 then raise exception 'Bút toán phải có ít nhất hai dòng.'; end if;
  if tdr <> tcr then raise exception 'Bút toán không cân: tổng Nợ % khác tổng Có %.', erp_fm(tdr), erp_fm(tcr); end if;
  return jsonb_build_object('je', v_id, 'lines', outl, 'date', to_char(v_date,'YYYY-MM-DD'));
end $$;

-- Ghi một chứng từ mới (dùng chung cho tạo chứng từ, bút toán tự đảo, khớp sao kê)
create or replace function erp_doc_ins(p_co text, p_type text, p_status text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s int; v_id text; v_no text; pre text;
begin
  select coalesce(max(seq),0) + 1 into s from erp_doc where co = p_co and type = p_type;
  pre := case p_type when 'PR' then '100000' when 'PO' then '450000' when 'GR' then '500000' when 'IV' then '510000'
                     when 'PAY' then '150000' when 'SO' then '000010' when 'DL' then '800000' when 'BI' then '900000'
                     when 'RC' then '140000' when 'JE' then '010000' when 'CJ' then '030000' when 'CNT' then '040000'
                     when 'BS' then '050000' when 'ADV' then '060000' when 'ADS' then '070000' else '990000' end;
  v_id := p_type || lpad(s::text, 5, '0'); v_no := pre || lpad(s::text, 4, '0');
  insert into erp_doc(co,id,type,seq,status,data)
  values (p_co, v_id, p_type, s, p_status, p_data || jsonb_build_object('type',p_type,'seq',s,'no',v_no,'status',p_status));
  return jsonb_build_object('id', v_id, 'no', v_no, 'seq', s);
end $$;

-- Kiểm tra một dòng bút toán tay (FB50, FBCJ, quyết toán tạm ứng): TK cho phép ghi tay, không phải TK đối chiếu, có TTCP nếu bắt buộc
create or replace function erp_manual_line(p_co text, p_acc text, p_cc text, p_cash_ok boolean) returns erp_acct
language plpgsql stable set search_path = public, extensions as $$
declare a erp_acct;
begin
  select * into a from erp_acct where code = p_acc and active;
  if not found then raise exception 'Tài khoản % không có trong hệ thống tài khoản.', p_acc; end if;
  if a.recon is not null then
    raise exception 'TK % là tài khoản đối chiếu (%): chỉ ghi qua chứng từ nghiệp vụ của phân hệ, không hạch toán tay.', a.code,
      case a.recon when 'AR' then 'phải thu' when 'AP' then 'phải trả' when 'INV' then 'tồn kho' when 'ADV' then 'tạm ứng' when 'FA' then 'tài sản cố định' else 'tiền lương' end; end if;
  if not a.manual then raise exception 'TK % không cho phép hạch toán tay; số liệu do hệ thống tự ghi.', a.code; end if;
  if not p_cash_ok and a.code in (erp_ad('CASH'), erp_ad('BANK'), erp_ad('BANK_CLR')) then
    raise exception 'TK % là tài khoản tiền: dùng FBCJ (tiền mặt) hoặc sao kê ngân hàng (FF67).', a.code; end if;
  if a.cc_req and not exists (select 1 from erp_org where co = p_co and kind = 'CC' and code = p_cc) then
    raise exception 'TK % bắt buộc chọn trung tâm chi phí.', a.code; end if;
  if coalesce(p_cc,'') <> '' and not exists (select 1 from erp_org where co = p_co and kind = 'CC' and code = p_cc) then
    raise exception 'Trung tâm chi phí % không tồn tại.', p_cc; end if;
  return a;
end $$;

-- ---------- Ngân hàng: phát hành sao kê theo ngày làm việc ----------
create or replace function erp_bank_seed(p_co text) returns void language plpgsql security definer set search_path = public, extensions as $$
declare m date := date_trunc('month', erp_wdate(p_co))::date;
begin
  delete from erp_bank_preset where co = p_co and not issued;
  insert into erp_bank_preset(co,id,vdate,kind,amt,descr)
  select p_co, coalesce((select max(id) from erp_bank_preset where co = p_co),0) + x.n, x.d, x.k, x.a, x.t from (values
    (1, m + 19, 'unk', 15000000::numeric, 'CTY CP THUY SAN HON TRE CHUYEN TIEN'),
    (2, m + 27, 'fee', -55000::numeric, 'PHI QUAN LY TAI KHOAN VA SMS BANKING THANG ' || to_char(m,'MM/YYYY')),
    (3, (m + interval '1 month - 1 day')::date, 'int', 1250000::numeric, 'TRA LAI TIEN GUI KHONG KY HAN THANG ' || to_char(m,'MM/YYYY'))
  ) as x(n,d,k,a,t);
end $$;
create or replace function erp_bank_issue(p_co text) returns int language plpgsql security definer set search_path = public, extensions as $$
declare wd date := erp_wdate(p_co); r record; k int := 0; s int;
begin
  perform pg_advisory_xact_lock(hashtext('erp:bank:' || p_co));
  select coalesce(max(substr(id,3)::int),0) into s from erp_bank_line where co = p_co;
  -- Chi chuyển khoản (PAY) và nộp tiền mặt vào ngân hàng (CJ dep) ghi qua TK 113: ngân hàng hạch toán ngày làm việc kế tiếp, chờ khớp ở FF67
  -- Thu có giấy báo Có (RC) và rút tiền gửi (CJ wd) đã ghi thẳng TK 112: dòng sao kê phát hành cùng ngày, ở trạng thái đã khớp
  for r in select d.id, d.type, d.data->>'dir' dir, (d.data->>'amount')::numeric amt, j.post_date, d.data->>'vendor' ven, d.data->>'cust' cus,
                  coalesce(d.data->>'bankAcc','') bacc, coalesce((d.data->>'bankDirect')::boolean,false) direct
             from erp_doc d join erp_je j on j.co = d.co and j.doc_id = d.id
            where d.co = p_co and d.status = 'posted'
              and ((d.type = 'PAY' and d.data->>'clr' = erp_ad('BANK_CLR'))
                or (d.type = 'CJ' and d.data->>'dir' = 'dep' and d.data->>'clr' = erp_ad('BANK_CLR'))
                or (d.type in ('RC','CJ') and coalesce((d.data->>'bankDirect')::boolean,false)))
              and j.post_date + case when coalesce((d.data->>'bankDirect')::boolean,false) then 0 else 1 end <= wd
              and not exists (select 1 from erp_bank_line b where b.co = p_co and b.ref_doc = d.id)
            order by j.post_date, d.id loop
    s := s + 1; k := k + 1;
    insert into erp_bank_line(co,id,vdate,amt,descr,kind,ref_doc,status,bs_doc,matched_at)
    values (p_co, 'SL' || lpad(s::text,5,'0'), r.post_date + case when r.direct then 0 else 1 end,
            case when r.type = 'PAY' or r.dir = 'wd' then -r.amt else r.amt end,
            case when r.type = 'PAY' then 'CHUYEN TIEN DEN ' || coalesce(r.ven,'') || ' TK ' || r.bacc
                 when r.type = 'RC' then 'NHAN TIEN TU ' || coalesce(r.cus,'')
                 when r.dir = 'wd' then 'RUT TIEN MAT TAI QUAY'
                 else 'NOP TIEN MAT VAO TAI KHOAN' end || ' REF ' || r.id, 'doc', r.id,
            case when r.direct then 'matched' else 'open' end, case when r.direct then r.id end, case when r.direct then clock_timestamp() end);
  end loop;
  for r in select * from erp_bank_preset where co = p_co and not issued and vdate <= wd order by vdate, id loop
    s := s + 1; k := k + 1;
    insert into erp_bank_line(co,id,vdate,amt,descr,kind,preset) values (p_co, 'SL' || lpad(s::text,5,'0'), r.vdate, r.amt, r.descr, r.kind, r.id);
    update erp_bank_preset set issued = true where co = p_co and id = r.id;
  end loop;
  return k;
end $$;
do $$ declare c text; begin
  foreach c in array erp_cos() loop
    if not exists (select 1 from erp_bank_preset where co = c) then perform erp_bank_seed(c); end if;
  end loop;
end $$;

-- ---------- Giảng viên: ngày làm việc, số kiểm đếm quỹ, khoản sao kê cài sẵn ----------
create or replace function erp_admin_set_state(p_token text, p_co text, p_state jsonb) returns jsonb language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user; c text; out jsonb := '{}'; nd date;
begin
  u := erp_require_admin(p_token);
  if p_state ? 'wdate' then nd := erp_date(p_state->>'wdate'); end if;
  foreach c in array erp_cos() loop
    if coalesce(p_co,'') <> '' and c <> p_co then continue; end if;
    insert into erp_co_state(co) values (c) on conflict do nothing;
    if nd is not null then
      if nd < coalesce((select max(post_date) from erp_je where co = c and doc_type = 'OB'), nd) then
        raise exception 'Ngày làm việc không được trước ngày mở sổ.'; end if;
      update erp_co_state set wdate = nd, updated_at = clock_timestamp() where co = c;
    end if;
    if p_state ? 'cashCount' then
      update erp_co_state set cash_count = case when coalesce(p_state->>'cashCount','') = '' then null else round((p_state->>'cashCount')::numeric) end,
             updated_at = clock_timestamp() where co = c;
    end if;
    if coalesce((p_state->>'reseed')::boolean, false) then perform erp_bank_seed(c); update erp_co_state set updated_at = clock_timestamp() where co = c; end if;
    out := out || jsonb_build_object(c, erp_bank_issue(c));
  end loop;
  return out;
end $$;

-- ---------- OB52: đóng / mở kỳ ----------
create or replace function erp_period_set(p_token text, p_co text, p_fy int, p_period int, p_grp text, p_close boolean, p_act_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u erp_user;
begin
  u := erp_auth(p_token);
  if not u.is_admin and p_co is distinct from u.co then raise exception 'Không được đóng/mở kỳ của công ty khác.'; end if;
  if not erp_can(erp_act_roles(u, p_act_role), 'OB52', 'A') then raise exception 'Chỉ Kế toán trưởng được đóng/mở kỳ kế toán (OB52).'; end if;
  if p_grp not in ('+','MM','AR','AP','AA','GL') or p_period not between 1 and 12 or p_fy not between 2020 and 2100 then
    raise exception 'Kỳ hoặc nhóm tài khoản không hợp lệ.'; end if;
  if p_close then
    insert into erp_period_close(co,fy,period,grp,by) values (p_co,p_fy,p_period,p_grp,u.id) on conflict do nothing;
  else
    delete from erp_period_close where co = p_co and fy = p_fy and period = p_period and grp = p_grp;
  end if;
  insert into erp_period_log(co,fy,period,grp,act,by) values (p_co,p_fy,p_period,p_grp,case when p_close then 'close' else 'open' end,u.id);
  update erp_co_state set updated_at = clock_timestamp() where co = p_co;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- FF67: khớp dòng sao kê ----------
-- Chứng từ BS ghi: chi qua NH Nợ 113/Có 112; thu qua NH Nợ 112/Có 113; phí Nợ 6427 (CC700)/Có 112; lãi Nợ 112/Có 515;
-- tiền về chưa rõ nội dung: Nợ 112/Có 131 (nếu xác định được khách hàng) hoặc Có 3388 (chờ xác định).
create or replace function erp_bank_match(p_token text, p_co text, p_line text, p_opts jsonb, p_act_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u erp_user; r text; b erp_bank_line; lines jsonb; posted jsonb; ins jsonb; ts text := erp_iso(); x numeric; bi jsonb; memo text; rem numeric; extra jsonb := '{}';
begin
  u := erp_auth(p_token);
  if not u.is_admin and p_co is distinct from u.co then raise exception 'Không được xử lý sao kê của công ty khác.'; end if;
  if not erp_can(erp_act_roles(u, p_act_role), 'FF67', 'C') then raise exception 'Vai trò của bạn không được xử lý sao kê ngân hàng (FF67).'; end if;
  r := case when u.is_admin then coalesce(nullif(p_act_role,''),'GV') else 'TH' end;
  perform pg_advisory_xact_lock(hashtext('erp:doc:' || p_co));
  select * into b from erp_bank_line where co = p_co and id = p_line for update;
  if not found then raise exception 'Không tìm thấy dòng sao kê.'; end if;
  if b.status <> 'open' then raise exception 'Dòng sao kê này đã được xử lý.'; end if;
  x := abs(b.amt);
  if b.kind = 'doc' then
    lines := case when b.amt < 0
      then jsonb_build_array(jsonb_build_object('a',erp_ad('BANK_CLR'),'dr',x), jsonb_build_object('a',erp_ad('BANK'),'cr',x))
      else jsonb_build_array(jsonb_build_object('a',erp_ad('BANK'),'dr',x), jsonb_build_object('a',erp_ad('BANK_CLR'),'cr',x)) end;
    memo := 'Khớp sao kê với chứng từ ' || b.ref_doc;
  elsif b.kind = 'fee' then
    lines := jsonb_build_array(jsonb_build_object('a',erp_ad('BANK_FEE'),'dr',x,'cc','CC700'), jsonb_build_object('a',erp_ad('BANK'),'cr',x));
    memo := 'Phí ngân hàng theo sao kê';
  elsif b.kind = 'int' then
    lines := jsonb_build_array(jsonb_build_object('a',erp_ad('BANK'),'dr',x), jsonb_build_object('a',erp_ad('INT_INC'),'cr',x));
    memo := 'Lãi tiền gửi theo sao kê';
  else
    if coalesce(p_opts->>'bi','') <> '' then
      bi := erp_doc_data(p_co, p_opts->>'bi');
      if bi is null or bi->>'type' <> 'BI' or bi->>'status' <> 'posted' then raise exception 'Hóa đơn bán không hợp lệ.'; end if;
      rem := (bi->>'total')::numeric - erp_kid_amt(p_co,'RC','bi',p_opts->>'bi') - erp_bs_alloc(p_co, p_opts->>'bi');
      if x > rem then raise exception 'Số tiền về (% đồng) lớn hơn phần còn nợ của hóa đơn (% đồng). Ghi treo TK 3388 rồi phân bổ từng phần.', erp_fm(x), erp_fm(rem); end if;
      lines := jsonb_build_array(jsonb_build_object('a',erp_ad('BANK'),'dr',x), jsonb_build_object('a',erp_ad('AR'),'cr',x,'p',bi->>'cust'));
      memo := 'Khách hàng ' || (bi->>'cust') || ' trả hóa đơn ' || (bi->>'invSym') || ' số ' || (bi->>'invNo') || ' (xác định theo sao kê)';
      extra := jsonb_build_object('bi', p_opts->>'bi', 'cust', bi->>'cust', 'alloc', x);
    else
      lines := jsonb_build_array(jsonb_build_object('a',erp_ad('BANK'),'dr',x), jsonb_build_object('a',erp_ad('SUSPENSE'),'cr',x));
      memo := 'Tiền về chưa rõ nội dung, treo TK 3388 chờ xác định';
    end if;
  end if;
  ins := erp_doc_ins(p_co, 'BS', 'posted', jsonb_build_object('line',b.id,'kind',b.kind,'amount',b.amt,'vdate',to_char(b.vdate,'YYYY-MM-DD'),
           'date',to_char(erp_wdate(p_co),'YYYY-MM-DD'),'descr',b.descr,'ref',b.ref_doc,'memo',memo,
           'at',ts,'by',u.id::text,'role',r,'hist',jsonb_build_array(jsonb_build_object('at',ts,'by',u.id::text,'role',r,'act','create','note',memo))) || extra);
  posted := erp_post(p_co, ins->>'id', 'BS', null, u.id, lines, memo);
  update erp_doc set data = data || jsonb_build_object('je',posted->'lines','jeNo',posted->>'je','pdate',posted->>'date'), updated_at = clock_timestamp()
   where co = p_co and id = ins->>'id';
  update erp_bank_line set status = 'matched', bs_doc = ins->>'id', matched_by = u.id, matched_at = clock_timestamp(), updated_at = clock_timestamp()
   where co = p_co and id = b.id;
  return ins;
end $$;
create or replace function erp_bank_refresh(p_token text, p_co text) returns int language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user;
begin
  u := erp_auth(p_token);
  if not u.is_admin and p_co is distinct from u.co then raise exception 'Không được xem sao kê của công ty khác.'; end if;
  if not u.is_admin and not exists (select 1 from erp_role_perm where role = any(erp_roles_of(u)) and tc = 'FF67') then
    raise exception 'Vai trò của bạn không được nhận sao kê ngân hàng (FF67).'; end if;
  return erp_bank_issue(p_co);
end $$;

-- ---------- Làm mới công ty: xóa thêm sao kê, kỳ đã đóng ----------
create or replace function erp_purge_co(p_co text) returns void language plpgsql
security definer set search_path = public, extensions as $$
begin
  perform set_config('erp.allow_purge', 'on', true);
  delete from erp_je_line where co = p_co;
  delete from erp_je where co = p_co;
  perform set_config('erp.allow_purge', '', true);
  delete from erp_doc where co = p_co;
  delete from erp_val where co = p_co;
  delete from erp_bank_line where co = p_co;
  delete from erp_period_close where co = p_co;
  update erp_bank_preset set issued = false where co = p_co;
  update erp_co_state set updated_at = clock_timestamp() where co = p_co;
  perform erp_open_co(p_co);
end $$;

create or replace function erp_admin_set_cfg(p_token text, p_cfg jsonb) returns jsonb language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user; nv jsonb;
begin
  u := erp_require_admin(p_token);
  nv := jsonb_build_object('tol', greatest(0, least(50, coalesce((p_cfg->>'tol')::numeric, 5))),
                          'poAuto', greatest(0, coalesce((p_cfg->>'poAuto')::numeric, 0)),
                          'credit', coalesce((p_cfg->>'credit')::boolean, true),
                          'selfApprove', coalesce((p_cfg->>'selfApprove')::boolean, false),
                          'bankClear', coalesce((p_cfg->>'bankClear')::boolean, true),
                          'vat', case when (p_cfg->>'vat') in ('0','0.05','0.08','0.1','0.10') then (p_cfg->>'vat')::numeric else erp_vat() end);
  update erp_cfg set v = v || nv where k = 'main';
  return nv;
end $$;


-- ---------- Sau rà soát độc lập P3 (RV-xx): hàm bổ sung ----------
-- Tài khoản đối ứng được phép theo loại chứng từ tiền mặt / tạm ứng (RV-09)
create or replace function erp_acc_ok(p_ctx text, p_acc text) returns boolean language sql immutable set search_path = public, extensions as $$
  select case p_ctx
    when 'CJ_OUT' then p_acc ~ '^(6|811|1331|242|1381|1388|3381|3388|334|335|338)'
    when 'CJ_IN'  then p_acc ~ '^(711|515|1381|1388|3381|3388|338|344)'
    when 'ADS'    then p_acc ~ '^(6|811|1331|242)'
    else false end
$$;
-- Số đã thu trên hóa đơn bán qua phân bổ tiền về theo sao kê (RV-06, RV-07)
create or replace function erp_bs_alloc(p_co text, p_bi text) returns numeric language sql stable set search_path = public, extensions as $$
  select coalesce(sum((data->>'alloc')::numeric), 0) from erp_doc
   where co = p_co and type = 'BS' and status = 'posted' and data->>'bi' = p_bi and not (data ? 'revBy')
$$;
-- Tổng tiền chứng từ con còn hiệu lực (thêm trạng thái đã duyệt chờ thủ quỹ)
create or replace function erp_kid_amt(p_co text, p_type text, p_fld text, p_parent text) returns numeric
language sql stable set search_path = public, extensions as $$
  select coalesce(sum((data->>'amount')::numeric), 0) from erp_doc
   where co = p_co and type = p_type and status in ('pending','approved','posted') and data->>p_fld = p_parent
$$;
-- Dòng bút toán quyết toán tạm ứng
create or replace function erp_ads_lines(p jsonb) returns jsonb language plpgsql stable set search_path = public, extensions as $$
declare l jsonb := '[]'; it jsonb; r numeric := (p->>'ret')::numeric;
begin
  for it in select * from jsonb_array_elements(p->'lines') loop
    l := l || jsonb_build_object('a',it->>'a','dr',it->'amount','cc',it->>'cc','memo',it->>'memo');
  end loop;
  if r > 0 then l := l || jsonb_build_object('a',erp_ad('CASH'),'dr',r,'memo','Hoàn ứng nộp lại quỹ'); end if;
  if r < 0 then l := l || jsonb_build_object('a',erp_ad('CASH'),'cr',-r,'memo','Chi bổ sung phần vượt tạm ứng'); end if;
  return l || jsonb_build_object('a',erp_ad('ADV'),'cr',p->'advAmount','p',p->>'emp');
end $$;

-- Thủ quỹ xác nhận đã thu / đã chi tiền mặt → ghi TK 111 (RV-11, RV-13)
create or replace function erp_cash_confirm(p_token text, p_co text, p_id text, p_act_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u erp_user; r text; d erp_doc; nd jsonb; amt numeric; lines jsonb; posted jsonb; ts text := erp_iso(); ns text := 'posted'; memo text; pa erp_partner;
begin
  u := erp_auth(p_token);
  if not u.is_admin and p_co is distinct from u.co then raise exception 'Không được xác nhận thu chi của công ty khác.'; end if;
  if not erp_can(erp_act_roles(u, p_act_role), 'ZTQ', 'C') then raise exception 'Chỉ Thủ quỹ xác nhận đã thu, đã chi tiền mặt.'; end if;
  r := case when u.is_admin then coalesce(nullif(p_act_role,''),'GV') else 'TQ' end;
  perform pg_advisory_xact_lock(hashtext('erp:doc:' || p_co));
  select * into d from erp_doc where co = p_co and id = p_id for update;
  if not found then raise exception 'Không tìm thấy chứng từ.'; end if;
  if d.status <> 'approved' or d.type not in ('PAY','RC','CJ','ADV','ADS') or (d.type in ('PAY','RC') and d.data->>'acc' <> erp_ad('CASH')) then
    raise exception 'Chứng từ không ở trạng thái chờ thủ quỹ thu, chi.'; end if;
  if d.data->>'by' = u.id::text and not u.is_admin then raise exception 'Vi phạm bất kiêm nhiệm: người lập chứng từ không tự thu, chi tiền.'; end if;
  if d.type in ('ADV','ADS') and d.data->>'emp' = u.username and not u.is_admin then
    raise exception 'Vi phạm bất kiêm nhiệm: Thủ quỹ không tự chi tạm ứng hoặc tự quyết toán tạm ứng cho chính mình.'; end if;
  amt := (d.data->>'amount')::numeric; nd := d.data;
  if d.type = 'PAY' then
    select * into pa from erp_partner where co = p_co and code = d.data->>'vendor';
    if not pa.active then raise exception 'Nhà cung cấp % đang bị khóa (XK02): không chi tiền.', pa.code; end if;
    lines := jsonb_build_array(jsonb_build_object('a',erp_ad('AP'),'dr',amt,'p',d.data->>'vendor'), jsonb_build_object('a',erp_ad('CASH'),'cr',amt));
  elsif d.type = 'RC' then
    lines := jsonb_build_array(jsonb_build_object('a',erp_ad('CASH'),'dr',amt), jsonb_build_object('a',erp_ad('AR'),'cr',amt,'p',d.data->>'cust'));
  elsif d.type = 'ADV' then
    lines := jsonb_build_array(jsonb_build_object('a',erp_ad('ADV'),'dr',amt,'p',d.data->>'emp','memo','Chi tạm ứng ' || (d.data->>'no')),
                               jsonb_build_object('a',erp_ad('CASH'),'cr',amt));
    ns := 'paid';
  elsif d.type = 'ADS' then
    lines := erp_ads_lines(d.data);
  elsif d.data->>'dir' = 'out' then
    lines := jsonb_build_array(jsonb_build_object('a',d.data->>'acc','dr',amt,'cc',d.data->>'cc'), jsonb_build_object('a',erp_ad('CASH'),'cr',amt));
  elsif d.data->>'dir' = 'in' then
    lines := jsonb_build_array(jsonb_build_object('a',erp_ad('CASH'),'dr',amt), jsonb_build_object('a',d.data->>'acc','cr',amt,'cc',d.data->>'cc'));
  elsif d.data->>'dir' = 'wd' then
    -- Rút tiền gửi về quỹ: giấy báo Nợ của ngân hàng có ngay → ghi thẳng Có 112
    lines := jsonb_build_array(jsonb_build_object('a',erp_ad('CASH'),'dr',amt), jsonb_build_object('a',erp_ad('BANK'),'cr',amt));
    nd := nd || jsonb_build_object('bankDirect', true);
  else
    -- Nộp tiền mặt vào ngân hàng, chưa có giấy báo Có → TK 113 đến khi có sao kê
    lines := jsonb_build_array(jsonb_build_object('a',erp_ad('BANK_CLR'),'dr',amt), jsonb_build_object('a',erp_ad('CASH'),'cr',amt));
    nd := nd || jsonb_build_object('clr', erp_ad('BANK_CLR'));
  end if;
  if exists (select 1 from jsonb_array_elements(lines) x where x->>'a' = erp_ad('CASH') and coalesce((x->>'cr')::numeric,0) > 0)
     and erp_balance(p_co, erp_ad('CASH')) < (select sum(coalesce((x->>'cr')::numeric,0)) from jsonb_array_elements(lines) x where x->>'a' = erp_ad('CASH')) then
    raise exception 'Không đủ tồn quỹ tiền mặt (còn % đồng). Tồn quỹ không được âm.', erp_fm(erp_balance(p_co, erp_ad('CASH'))); end if;
  memo := coalesce(d.data->>'reason', d.data->>'memo', d.data->>'purpose', '');
  posted := erp_post(p_co, d.id, d.type, null, u.id, lines, memo);
  nd := nd || jsonb_build_object('je', posted->'lines', 'jeNo', posted->>'je', 'pdate', posted->>'date', 'status', ns, 'cashBy', u.id::text, 'cashAt', ts,
        'hist', coalesce(nd->'hist','[]'::jsonb) || jsonb_build_array(jsonb_build_object('at',ts,'by',u.id::text,'role',r,'act','cash','note','')));
  update erp_doc set status = ns, data = nd, updated_at = clock_timestamp() where co = p_co and id = p_id;
  if d.type = 'ADS' then
    update erp_doc set status = 'settled', updated_at = clock_timestamp(),
      data = data || jsonb_build_object('status','settled','setBy',d.id,'setNo',d.data->>'no') where co = p_co and id = d.data->>'adv';
  end if;
  return jsonb_build_object('status', ns, 'je', posted->>'je');
end $$;

-- Phân bổ khoản tiền về đang treo 3388 cho một hóa đơn bán (RV-06)
create or replace function erp_susp_clear(p_token text, p_co text, p_bs text, p_bi text, p_amount numeric, p_act_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u erp_user; r text; s jsonb; bi jsonb; rem_s numeric; rem_b numeric; amt numeric := round(coalesce(p_amount,0)); ins jsonb; posted jsonb; ts text := erp_iso(); memo text;
begin
  u := erp_auth(p_token);
  if not u.is_admin and p_co is distinct from u.co then raise exception 'Không được xử lý chứng từ của công ty khác.'; end if;
  if not erp_can(erp_act_roles(u, p_act_role), 'FF67', 'C') then raise exception 'Vai trò của bạn không được xử lý sao kê ngân hàng (FF67).'; end if;
  r := case when u.is_admin then coalesce(nullif(p_act_role,''),'GV') else 'TH' end;
  perform pg_advisory_xact_lock(hashtext('erp:doc:' || p_co));
  s := erp_doc_data(p_co, p_bs);
  if s is null or s->>'type' <> 'BS' or s->>'kind' <> 'unk' or coalesce(s->>'bi','') <> '' or s ? 'revBy' then
    raise exception 'Chỉ phân bổ được khoản tiền về chưa rõ nội dung đang treo TK 3388.'; end if;
  bi := erp_doc_data(p_co, p_bi);
  if bi is null or bi->>'type' <> 'BI' or bi->>'status' <> 'posted' then raise exception 'Hóa đơn bán không hợp lệ.'; end if;
  rem_s := abs((s->>'amount')::numeric) - coalesce((select sum((data->>'alloc')::numeric) from erp_doc where co = p_co and type = 'BS' and data->>'ref' = p_bs and status = 'posted' and not (data ? 'revBy')),0);
  rem_b := (bi->>'total')::numeric - erp_kid_amt(p_co,'RC','bi',p_bi) - erp_bs_alloc(p_co, p_bi);
  if amt <= 0 or amt > rem_s or amt > rem_b then
    raise exception 'Số tiền phân bổ phải lớn hơn 0, không vượt phần còn treo (% đồng) và phần còn nợ của hóa đơn (% đồng).', erp_fm(rem_s), erp_fm(rem_b); end if;
  memo := 'Phân bổ tiền về chưa rõ (' || (s->>'no') || ') cho hóa đơn ' || (bi->>'invSym') || ' số ' || (bi->>'invNo');
  ins := erp_doc_ins(p_co, 'BS', 'posted', jsonb_build_object('kind','clr','ref',p_bs,'bi',p_bi,'cust',bi->>'cust','alloc',amt,'amount',amt,
           'date',to_char(erp_wdate(p_co),'YYYY-MM-DD'),'memo',memo,'at',ts,'by',u.id::text,'role',r,
           'hist',jsonb_build_array(jsonb_build_object('at',ts,'by',u.id::text,'role',r,'act','create','note',memo))));
  posted := erp_post(p_co, ins->>'id', 'BS', null, u.id,
    jsonb_build_array(jsonb_build_object('a',erp_ad('SUSPENSE'),'dr',amt), jsonb_build_object('a',erp_ad('AR'),'cr',amt,'p',bi->>'cust')), memo);
  update erp_doc set data = data || jsonb_build_object('je',posted->'lines','jeNo',posted->>'je','pdate',posted->>'date'), updated_at = clock_timestamp()
   where co = p_co and id = ins->>'id';
  return ins;
end $$;

-- ---------- Lập chứng từ (thay bản 004) ----------
create or replace function erp_doc_create(p_token text, p_co text, p_type text, p_body jsonb, p_note text, p_act_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  u erp_user; r text; st text; s int; v_id text; v_no text; ts text := erp_iso(); roles text[];
  pre text; po_auto numeric; b jsonb := p_body; src jsonb; it jsonb; items jsonb := '[]'; je jsonb := '[]';
  q numeric; pr numeric; i int; net numeric := 0; vat numeric; total numeric; rate numeric := erp_vat();
  tol numeric; cfg jsonb; m erp_mat; pa erp_partner; d date; diff numeric; diffsum numeric := 0; bad text := '';
  cost numeric; costsum numeric := 0; amt numeric; rem numeric; posted jsonb; note text := coalesce(p_note,'');
  wd date; v_roles text[]; a erp_acct; tot numeric := 0; jkind text; v_exp numeric := 0;
begin
  u := erp_auth(p_token);
  if not u.is_admin then
    if u.co is null or u.role is null then raise exception 'Bạn chưa được giảng viên phân công vào công ty.'; end if;
    if p_co is distinct from u.co then raise exception 'Không được ghi chứng từ cho công ty khác.'; end if;
  end if;
  if not (p_co = any(erp_cos())) then raise exception 'Mã công ty không hợp lệ.'; end if;
  if jsonb_typeof(b) <> 'object' then raise exception 'Dữ liệu chứng từ không hợp lệ.'; end if;
  if p_type not in ('PR','PO','GR','IV','PAY','SO','DL','BI','RC','JE','CJ','CNT','ADV','ADS') then raise exception 'Loại chứng từ % không tồn tại.', p_type; end if;
  if u.is_admin then
    roles := erp_act_roles(u, p_act_role);
    if not erp_can(roles, erp_type_tc(p_type), 'C') then
      raise exception 'Vai trò % không được lập loại chứng từ này (SU53).', p_act_role; end if;
    r := case when roles = array['GV'] then 'GV' else p_act_role end;
  else
    r := erp_role_for(u, p_type);
    if r is null then
      raise exception 'Bạn chưa được giao quyền lập loại chứng từ này (SU53). Nhờ giảng viên giao kiêm nhiệm nếu nhóm thiếu người.';
    end if;
  end if;
  v_roles := case when u.is_admin then roles else erp_roles_of(u) end;
  b := b - 'je' - 'status' - 'net' - 'vat' - 'total' - 'value' - 'invNo' - 'blockReason' - 'jeNo' - 'hist' - 'by' - 'at' - 'no' - 'seq' - 'type' - 'bankAcc' - 'pdate' - 'clr' - 'revBy' - 'revNo' - 'book' - 'counted' - 'diff' - 'emp' - 'empName' - 'expTotal' - 'ret' - 'advAmount' - 'revDate' - 'kind_' - 'auto' - 'amount_';
  d := erp_date(b->>'date');
  wd := erp_wdate(p_co);
  if d > wd then raise exception 'Ngày chứng từ % sau ngày làm việc % của công ty. Hệ thống không ghi nghiệp vụ tương lai.', to_char(d,'DD/MM/YYYY'), to_char(wd,'DD/MM/YYYY'); end if;
  select v into cfg from erp_cfg where k = 'main';
  tol := coalesce((cfg->>'tol')::numeric, 5);

  perform pg_advisory_xact_lock(hashtext('erp:doc:' || p_co));

  if p_type in ('PR','SO') then
    if jsonb_typeof(b->'items') <> 'array' or jsonb_array_length(b->'items') = 0 then raise exception 'Chứng từ chưa có dòng hàng.'; end if;
    if p_type = 'SO' then
      select * into pa from erp_partner where co = p_co and code = b->>'cust' and kind = 'C';
      if not found then raise exception 'Khách hàng không hợp lệ.'; end if;
      if not pa.active then raise exception 'Khách hàng % đang bị khóa (XD02).', pa.code; end if;
      if not pa.confirmed then raise exception 'Khách hàng % chưa được Kế toán trưởng xác nhận dữ liệu gốc (ZMDA).', pa.code; end if;
      if coalesce(trim(b->>'custPo'),'') = '' then raise exception 'Thiếu số đơn đặt hàng của khách. Đơn bán phải có căn cứ.'; end if;
    else
      if coalesce(trim(b->>'reason'),'') = '' then raise exception 'Thiếu lý do đề nghị.'; end if;
    end if;
    for it in select * from jsonb_array_elements(b->'items') loop
      select * into m from erp_mat where co = p_co and code = it->>'mat';
      if not found then raise exception 'Mã hàng % không có trong danh mục.', it->>'mat'; end if;
      if not m.active then raise exception 'Vật tư % đang bị khóa (MM02).', m.code; end if;
      if m.valid_from > d then raise exception 'Vật tư % chỉ có hiệu lực từ %.', m.code, to_char(m.valid_from,'DD/MM/YYYY'); end if;
      if p_type = 'PR' and m.mtype not in ('HH','NVL') then raise exception 'Vật tư % (loại %) không mua ngoài được.', m.code, m.mtype; end if;
      if p_type = 'SO' and m.mtype not in ('HH','TP') then raise exception 'Vật tư % (loại %) chưa bán được ở giai đoạn này; dịch vụ có từ P5.', m.code, m.mtype; end if;
      q := erp_num(it,'qty'); if q is null or q <= 0 or q <> trunc(q) then raise exception 'Số lượng phải là số nguyên lớn hơn 0.'; end if;
      if items @> jsonb_build_array(jsonb_build_object('mat', m.code)) then raise exception 'Trùng mặt hàng %. Gộp các dòng cùng mã hàng.', m.code; end if;
      if p_type = 'SO' then
        pr := erp_num(it,'price'); if pr is null or pr <= 0 then raise exception 'Đơn giá phải lớn hơn 0.'; end if;
        pr := round(pr); net := net + q*pr;
        items := items || jsonb_build_object('mat',m.code,'qty',q,'price',pr);
      else
        items := items || jsonb_build_object('mat',m.code,'qty',q);
      end if;
    end loop;
    b := b || jsonb_build_object('items', items);
    if p_type = 'PR' then st := 'pending';
    else
      vat := round(net*rate); total := net + vat;
      b := b || jsonb_build_object('net',net,'vat',vat,'total',total,'vatRate',rate);
      if coalesce((cfg->>'credit')::boolean, true) and erp_exposure(p_co, pa.code) + total > pa.credit_lim then
        st := 'blocked';
        b := b || jsonb_build_object('blockReason','Vượt hạn mức tín dụng ' || erp_fm(erp_exposure(p_co, pa.code) + total - pa.credit_lim) || ' đồng');
        note := 'Kiểm tra tín dụng: vượt hạn mức';
      else st := 'approved'; note := 'Kiểm tra tín dụng: đạt'; end if;
    end if;

  elsif p_type = 'PO' then
    src := erp_doc_data(p_co, b->>'pr');
    if src is null or src->>'status' <> 'approved' then raise exception 'Đề nghị mua chưa được duyệt hoặc không tồn tại.'; end if;
    if exists (select 1 from erp_doc where co = p_co and type = 'PO' and status <> 'rejected' and data->>'pr' = b->>'pr') then
      raise exception 'Đề nghị mua này đã được lập đơn mua.'; end if;
    select * into pa from erp_partner where co = p_co and code = b->>'vendor' and kind = 'V';
    if not found then raise exception 'Nhà cung cấp không hợp lệ.'; end if;
    if not pa.active then raise exception 'Nhà cung cấp % đang bị khóa (XK02).', pa.code; end if;
    if not pa.confirmed then raise exception 'Nhà cung cấp % chưa được Kế toán trưởng xác nhận dữ liệu gốc (ZMDA).', pa.code; end if;
    if jsonb_typeof(b->'items') <> 'array' or jsonb_array_length(b->'items') <> jsonb_array_length(src->'items') then
      raise exception 'Đơn mua phải gồm đúng các dòng của đề nghị mua.'; end if;
    for i in 0 .. jsonb_array_length(src->'items') - 1 loop
      it := b->'items'->i;
      if it->>'mat' is distinct from src->'items'->i->>'mat' or erp_num(it,'qty') is distinct from erp_num(src->'items'->i,'qty') then
        raise exception 'Dòng % của đơn mua khác đề nghị mua đã duyệt (mã hàng hoặc số lượng).', i+1; end if;
      pr := round(coalesce(erp_num(it,'price'),0)); if pr <= 0 then raise exception 'Đơn giá phải lớn hơn 0.'; end if;
      q := erp_num(it,'qty'); net := net + q*pr;
      items := items || jsonb_build_object('mat',it->>'mat','qty',q,'price',pr);
    end loop;
    vat := round(net*rate); total := net + vat;
    b := b || jsonb_build_object('items',items,'net',net,'vat',vat,'total',total,'vatRate',rate,'terms',pa.terms);
    po_auto := coalesce((cfg->>'poAuto')::numeric, 0);
    if po_auto > 0 and total <= po_auto then st := 'approved'; note := 'Tự duyệt do giá trị dưới hạn mức';
    else st := 'pending'; end if;

  elsif p_type = 'GR' then
    src := erp_doc_data(p_co, b->>'po');
    if src is null or src->>'status' <> 'approved' then raise exception 'Đơn mua chưa được duyệt hoặc không tồn tại.'; end if;
    if coalesce(trim(b->>'dn'),'') = '' or coalesce(trim(b->>'deliverer'),'') = '' then raise exception 'Thiếu số phiếu giao hàng hoặc người giao.'; end if;
    if jsonb_typeof(b->'items') <> 'array' then raise exception 'Chưa có số lượng thực nhận.'; end if;
    for it in select * from jsonb_array_elements(b->'items') loop
      i := (it->>'line')::int; q := erp_num(it,'qty');
      if i is null or i < 0 or i >= jsonb_array_length(src->'items') then raise exception 'Dòng đơn mua không hợp lệ.'; end if;
      if q is null or q <= 0 then continue; end if;
      if items @> jsonb_build_array(jsonb_build_object('line', i)) then
        raise exception 'Dòng % bị lặp trong cùng chứng từ. Gộp số lượng vào một dòng.', i+1; end if;
      if q <> trunc(q) then raise exception 'Số lượng phải là số nguyên.'; end if;
      rem := erp_num(src->'items'->i,'qty') - erp_kid_qty(p_co,'GR','po',b->>'po',i);
      if q > rem then raise exception 'Nhập vượt đơn mua: % chỉ còn % cần nhận. Hàng giao thừa phải lập biên bản và trả lại NCC.', src->'items'->i->>'mat', rem; end if;
      pr := erp_num(src->'items'->i,'price');
      select * into m from erp_mat where co = p_co and code = src->'items'->i->>'mat';
      items := items || jsonb_build_object('line',i,'mat',m.code,'qty',q,'price',pr,'sloc',m.sloc);
      je := je || jsonb_build_object('a',m.acc,'dr',q*pr,'mat',m.code,'q',q);
      net := net + q*pr;
    end loop;
    if jsonb_array_length(items) = 0 then raise exception 'Chưa có số lượng thực nhận.'; end if;
    je := je || jsonb_build_object('a',erp_ad('AP'),'cr',net,'p',src->>'vendor');
    b := b || jsonb_build_object('items',items,'vendor',src->>'vendor','value',net);
    st := 'posted';

  elsif p_type = 'IV' then
    src := erp_doc_data(p_co, b->>'po');
    if src is null or src->>'status' <> 'approved' then raise exception 'Đơn mua chưa được duyệt hoặc không tồn tại.'; end if;
    b := b || jsonb_build_object('invSym', upper(trim(coalesce(p_body->>'invSym',''))), 'invNo', trim(coalesce(p_body->>'invNo','')));
    if b->>'invSym' = '' or b->>'invNo' = '' then raise exception 'Thiếu ký hiệu hoặc số hóa đơn.'; end if;
    if exists (select 1 from erp_doc where co = p_co and type = 'IV' and status <> 'rejected' and data->>'vendor' = src->>'vendor'
               and upper(data->>'invSym') = b->>'invSym' and ltrim(data->>'invNo','0') = ltrim(b->>'invNo','0')) then
      raise exception 'Hóa đơn trùng: hóa đơn %/% của nhà cung cấp này đã được ghi nhận.', b->>'invSym', b->>'invNo'; end if;
    for it in select * from jsonb_array_elements(coalesce(b->'items','[]')) loop
      i := (it->>'line')::int; q := erp_num(it,'qty'); pr := round(coalesce(erp_num(it,'price'),0));
      if i is null or i < 0 or i >= jsonb_array_length(src->'items') then raise exception 'Dòng đơn mua không hợp lệ.'; end if;
      if q is null or q <= 0 then continue; end if;
      if items @> jsonb_build_array(jsonb_build_object('line', i)) then
        raise exception 'Dòng % bị lặp trong cùng chứng từ. Gộp số lượng vào một dòng.', i+1; end if;
      if pr <= 0 then raise exception 'Đơn giá hóa đơn phải lớn hơn 0.'; end if;
      rem := erp_kid_qty(p_co,'GR','po',b->>'po',i) - erp_kid_qty(p_co,'IV','po',b->>'po',i);
      if q > rem then raise exception 'Số lượng hóa đơn vượt số đã nhập kho: % mới nhập % chưa có hóa đơn. Không ghi nhận hàng chưa về.', src->'items'->i->>'mat', rem; end if;
      diff := (pr - erp_num(src->'items'->i,'price')) * q;
      if abs(pr - erp_num(src->'items'->i,'price')) / erp_num(src->'items'->i,'price') * 100 > tol then
        bad := bad || case when bad = '' then '' else ', ' end || (src->'items'->i->>'mat'); end if;
      items := items || jsonb_build_object('line',i,'mat',src->'items'->i->>'mat','qty',q,'price',pr,'poPrice',erp_num(src->'items'->i,'price'));
      if diff <> 0 then
        je := je || jsonb_build_object('a',(select acc from erp_mat where co=p_co and code=src->'items'->i->>'mat'),
                     case when diff > 0 then 'dr' else 'cr' end, abs(diff),'mat',src->'items'->i->>'mat');
      end if;
      net := net + q*pr; diffsum := diffsum + diff;
    end loop;
    if jsonb_array_length(items) = 0 then raise exception 'Chưa có dòng nào trên hóa đơn.'; end if;
    vat := round(net*rate); total := net + vat;
    if erp_num(p_body,'gross') is not null and abs(erp_num(p_body,'gross') - total) > 1 then
      raise exception 'Số liệu không cân: tổng trên hóa đơn % khác số hệ thống tính %.', erp_fm(erp_num(p_body,'gross')), erp_fm(total); end if;
    je := je || jsonb_build_object('a',erp_ad('VAT_IN'),'dr',vat);
    je := je || jsonb_build_object('a',erp_ad('AP'), case when diffsum + vat >= 0 then 'cr' else 'dr' end, abs(diffsum+vat),'p',src->>'vendor');
    select * into pa from erp_partner where co = p_co and code = src->>'vendor';
    b := b || jsonb_build_object('items',items,'vendor',src->>'vendor','net',net,'vat',vat,'total',total,'vatRate',rate,
         'due', to_char(d + pa.terms, 'YYYY-MM-DD'));
    if bad <> '' then st := 'blocked'; b := b || jsonb_build_object('blockReason','Lệch giá vượt ' || tol || '%: ' || bad);
    else st := 'posted'; end if;

  elsif p_type = 'PAY' then
    src := erp_doc_data(p_co, b->>'iv');
    if src is null or src->>'status' <> 'posted' then raise exception 'Hóa đơn chưa ghi sổ hoặc đang bị khóa thanh toán.'; end if;
    amt := round(coalesce(erp_num(p_body,'amount'),0));
    rem := erp_num(src,'total') - erp_kid_amt(p_co,'PAY','iv',b->>'iv');
    if amt <= 0 or amt > rem then raise exception 'Số tiền không hợp lệ: chỉ được đề nghị tối đa % đồng.', erp_fm(rem); end if;
    if b->>'acc' not in (erp_ad('CASH'), erp_ad('BANK')) then raise exception 'Tài khoản chi phải là % hoặc %.', erp_ad('CASH'), erp_ad('BANK'); end if;
    select * into pa from erp_partner where co = p_co and code = src->>'vendor';
    if not pa.active then raise exception 'Nhà cung cấp % đang bị khóa (XK02): không được đề nghị thanh toán.', pa.code; end if;
    if b->>'acc' = erp_ad('BANK') and coalesce(pa.bank_acc,'') = '' then
      raise exception 'Nhà cung cấp % chưa có tài khoản ngân hàng đã duyệt. Cập nhật ở XK02 và chờ Kế toán trưởng duyệt.', pa.code; end if;
    b := b || jsonb_build_object('vendor',src->>'vendor','amount',amt);
    if b->>'acc' = erp_ad('BANK') then b := b || jsonb_build_object('bankAcc', pa.bank_acc, 'bankName', pa.bank_name); end if;
    st := 'pending';

  elsif p_type = 'DL' then
    src := erp_doc_data(p_co, b->>'so');
    if src is null or src->>'status' <> 'approved' then raise exception 'Đơn bán chưa được xác nhận.'; end if;
    if coalesce(trim(b->>'receiver'),'') = '' then raise exception 'Thiếu người nhận hàng.'; end if;
    for it in select * from jsonb_array_elements(coalesce(b->'items','[]')) loop
      i := (it->>'line')::int; q := erp_num(it,'qty');
      if i is null or i < 0 or i >= jsonb_array_length(src->'items') then raise exception 'Dòng đơn bán không hợp lệ.'; end if;
      if q is null or q <= 0 then continue; end if;
      if items @> jsonb_build_array(jsonb_build_object('line', i)) then
        raise exception 'Dòng % bị lặp trong cùng chứng từ. Gộp số lượng vào một dòng.', i+1; end if;
      if q <> trunc(q) then raise exception 'Số lượng phải là số nguyên.'; end if;
      rem := erp_num(src->'items'->i,'qty') - erp_kid_qty(p_co,'DL','so',b->>'so',i);
      if q > rem then raise exception 'Xuất vượt đơn bán: % chỉ còn %.', src->'items'->i->>'mat', rem; end if;
      select * into m from erp_mat where co = p_co and code = src->'items'->i->>'mat';
      cost := erp_val_out(p_co, m.code, q);
      items := items || jsonb_build_object('line',i,'mat',m.code,'qty',q,'cost',cost,'sloc',m.sloc);
      je := je || jsonb_build_object('a',m.acc,'cr',cost,'mat',m.code,'q',q);
      costsum := costsum + cost;
    end loop;
    if jsonb_array_length(items) = 0 then raise exception 'Chưa có số lượng xuất.'; end if;
    je := jsonb_build_array(jsonb_build_object('a',erp_ad('COGS'),'dr',costsum)) || je;
    b := b || jsonb_build_object('items',items,'cust',src->>'cust','value',costsum);
    st := 'posted';

  elsif p_type = 'BI' then
    src := erp_doc_data(p_co, b->>'dl');
    if src is null or src->>'status' <> 'posted' then raise exception 'Phiếu xuất chưa ghi sổ hoặc không tồn tại.'; end if;
    if exists (select 1 from erp_doc where co = p_co and type = 'BI' and data->>'dl' = b->>'dl') then raise exception 'Phiếu xuất này đã được lập hóa đơn.'; end if;
    for it in select * from jsonb_array_elements(src->'items') loop
      pr := erp_num(erp_doc_data(p_co, src->>'so')->'items'->((it->>'line')::int), 'price');
      q := erp_num(it,'qty'); net := net + q*pr;
      items := items || jsonb_build_object('line',(it->>'line')::int,'mat',it->>'mat','qty',q,'price',pr);
    end loop;
    vat := round(net*rate); total := net + vat;
    select * into pa from erp_partner where co = p_co and code = src->>'cust';
    je := jsonb_build_array(jsonb_build_object('a',erp_ad('AR'),'dr',total,'p',src->>'cust'),
                            jsonb_build_object('a',erp_ad('REV'),'cr',net),
                            jsonb_build_object('a',erp_ad('VAT_OUT'),'cr',vat));
    b := b || jsonb_build_object('items',items,'so',src->>'so','cust',src->>'cust','net',net,'vat',vat,'total',total,'vatRate',rate,
         'due', to_char(d + pa.terms, 'YYYY-MM-DD'),
         'invSym', '1C' || to_char(d,'YY') || 'T' || substr('ABCDEFGH', array_position(erp_cos(), p_co), 1) || 'A');
    st := 'posted';

  elsif p_type = 'RC' then
    src := erp_doc_data(p_co, b->>'bi');
    if src is null or src->>'status' <> 'posted' then raise exception 'Hóa đơn bán chưa ghi sổ.'; end if;
    amt := round(coalesce(erp_num(p_body,'amount'),0));
    rem := erp_num(src,'total') - erp_kid_amt(p_co,'RC','bi',b->>'bi') - erp_bs_alloc(p_co, b->>'bi');
    if amt <= 0 or amt > rem then raise exception 'Số tiền không hợp lệ: tối đa % đồng.', erp_fm(rem); end if;
    if coalesce(trim(b->>'ref'),'') = '' then raise exception 'Thiếu số giấy báo Có hoặc người nộp tiền.'; end if;
    if b->>'acc' not in (erp_ad('CASH'), erp_ad('BANK')) then raise exception 'Tài khoản thu phải là % hoặc %.', erp_ad('CASH'), erp_ad('BANK'); end if;
    b := b || jsonb_build_object('cust',src->>'cust','amount',amt,'memo','Thu tiền hóa đơn ' || (src->>'invSym') || ' số ' || (src->>'invNo'));
    st := 'pending';
  elsif p_type = 'JE' then
    jkind := coalesce(nullif(b->>'kind',''),'man');
    if jkind not in ('man','acc','rev') then raise exception 'Loại bút toán không hợp lệ.'; end if;
    if not erp_can(v_roles, case jkind when 'man' then 'FB50' when 'acc' then 'FBS1' else 'FB08' end, 'C') then
      raise exception 'Vai trò của bạn không được lập loại bút toán này (SU53).'; end if;
    if jkind = 'rev' then
      src := erp_doc_data(p_co, b->>'revOf');
      if src is null then raise exception 'Không tìm thấy chứng từ cần đảo.'; end if;
      if src->>'type' not in ('JE','BS') or src->>'kind' in ('rev','doc') or (src->>'type' = 'BS' and coalesce((src->>'auto')::boolean,false)) then
        raise exception 'FB08 chỉ đảo bút toán tổng hợp (FB50, FBS1) và chứng từ ghi sổ theo sao kê (phí, lãi, tiền về). Chứng từ nghiệp vụ được điều chỉnh bằng giao dịch của phân hệ.'; end if;
      if src->>'type' = 'BS' and exists (select 1 from erp_doc where co = p_co and type = 'BS' and data->>'ref' = src->>'id' and status = 'posted' and not (data ? 'revBy')) then
        raise exception 'Khoản tiền về này đã được phân bổ cho hóa đơn. Đảo các chứng từ phân bổ trước.'; end if;
      if src->>'status' <> 'posted' then raise exception 'Chỉ đảo được bút toán đã ghi sổ.'; end if;
      if src ? 'revBy' or exists (select 1 from erp_doc where co = p_co and type = 'JE' and status <> 'rejected' and data->>'revOf' = b->>'revOf') then
        raise exception 'Bút toán này đã được đảo hoặc đang có đề nghị đảo.'; end if;
      if coalesce(trim(b->>'reason'),'') = '' then raise exception 'Thiếu lý do đảo.'; end if;
      for it in select * from jsonb_array_elements(src->'je') loop
        items := items || jsonb_strip_nulls(jsonb_build_object('a',it->>'a','dr',it->'cr','cr',it->'dr','cc',it->>'cc','memo',it->>'memo'));
        net := net + coalesce(erp_num(it,'dr'),0);
      end loop;
      b := b || jsonb_build_object('lines', items, 'amount', net, 'revNo', src->>'no',
             'memo', 'Đảo bút toán ' || (src->>'no') || ': ' || trim(b->>'reason'));
    else
      if coalesce(trim(b->>'memo'),'') = '' then raise exception 'Thiếu diễn giải bút toán.'; end if;
      if jsonb_typeof(b->'lines') <> 'array' or jsonb_array_length(b->'lines') < 2 then raise exception 'Bút toán phải có ít nhất hai dòng.'; end if;
      for it in select * from jsonb_array_elements(b->'lines') loop
        a := erp_manual_line(p_co, it->>'a', it->>'cc', false);
        q := round(coalesce(erp_num(it,'dr'),0)); pr := round(coalesce(erp_num(it,'cr'),0));
        if q < 0 or pr < 0 or (q > 0) = (pr > 0) then raise exception 'Mỗi dòng ghi một bên Nợ hoặc Có với số tiền lớn hơn 0 (TK %).', a.code; end if;
        net := net + q; tot := tot + pr;
        items := items || jsonb_strip_nulls(jsonb_build_object('a',a.code,'dr',nullif(q,0),'cr',nullif(pr,0),'cc',nullif(it->>'cc',''),
                   'memo',nullif(trim(coalesce(it->>'memo','')),'')));
      end loop;
      if net <> tot then raise exception 'Bút toán không cân: tổng Nợ % khác tổng Có %.', erp_fm(net), erp_fm(tot); end if;
      b := b || jsonb_build_object('lines', items, 'amount', net, 'memo', trim(b->>'memo'));
      if jkind = 'acc' then b := b || jsonb_build_object('revDate', to_char(date_trunc('month', wd) + interval '1 month','YYYY-MM-DD')); end if;
    end if;
    b := b || jsonb_build_object('kind', jkind);
    st := 'pending';

  elsif p_type = 'CJ' then
    amt := round(coalesce(erp_num(p_body,'amount'),0));
    if coalesce(b->>'adv','') <> '' then
      raise exception 'Chi tạm ứng: Thủ quỹ xác nhận chi trên đề nghị tạm ứng đã duyệt (FBCJ – Chờ thủ quỹ).'; end if;
    if coalesce(b->>'dir','') not in ('in','out','wd','dep') then
      raise exception 'Chọn loại phiếu: thu, chi, rút tiền gửi về quỹ hoặc nộp tiền mặt vào ngân hàng.'; end if;
    if amt <= 0 then raise exception 'Số tiền phải lớn hơn 0.'; end if;
    if coalesce(trim(b->>'person'),'') = '' or coalesce(trim(b->>'reason'),'') = '' then raise exception 'Thiếu người nộp/nhận tiền hoặc lý do.'; end if;
    if b->>'dir' in ('wd','dep') then
      b := (b || jsonb_build_object('amount', amt, 'acc', erp_ad('BANK'))) - 'cc';
    else
      a := erp_manual_line(p_co, b->>'acc', b->>'cc', false);
      if not erp_acc_ok(case b->>'dir' when 'out' then 'CJ_OUT' else 'CJ_IN' end, a.code) then
        raise exception 'TK % không dùng cho % tiền mặt. Thu nợ khách dùng F-28, trả nhà cung cấp dùng F-53; góp vốn, thuế phải nộp lập chứng từ riêng.', a.code,
          case b->>'dir' when 'out' then 'phiếu chi' else 'phiếu thu' end; end if;
      b := b || jsonb_build_object('amount', amt, 'acc', a.code);
      if coalesce(b->>'cc','') = '' then b := b - 'cc'; end if;
    end if;
    st := 'pending';

  elsif p_type = 'CNT' then
    select cash_count into amt from erp_co_state where co = p_co;
    if amt is null then raise exception 'Giảng viên chưa nhập số tiền kiểm đếm thực tế (SPRO). Chưa kiểm quỹ được.'; end if;
    if coalesce(trim(b->>'members'),'') = '' then raise exception 'Ghi thành phần ban kiểm kê quỹ.'; end if;
    if exists (select 1 from erp_doc where co = p_co and type in ('CJ','CNT') and status in ('pending','approved')) then
      raise exception 'Còn phiếu thu, phiếu chi hoặc biên bản kiểm quỹ chờ duyệt. Xử lý xong mới kiểm quỹ.'; end if;
    if erp_period_closed(p_co, wd, 'GL') then raise exception 'Kỳ %/% đã đóng. Không lập biên bản kiểm kê quỹ vào kỳ đã khóa sổ.', to_char(wd,'MM'), to_char(wd,'YYYY'); end if;
    rem := erp_balance(p_co, erp_ad('CASH'));
    diff := amt - rem;
    b := b || jsonb_build_object('book', rem, 'counted', amt, 'diff', diff);
    if diff = 0 then st := 'posted';
    else st := 'pending'; b := b || jsonb_build_object('reason', coalesce(nullif(trim(b->>'reason'),''), 'Chưa rõ nguyên nhân, chờ xử lý')); end if;

  elsif p_type = 'ADV' then
    amt := round(coalesce(erp_num(p_body,'amount'),0));
    if amt <= 0 then raise exception 'Số tiền tạm ứng phải lớn hơn 0.'; end if;
    if coalesce(trim(b->>'purpose'),'') = '' then raise exception 'Ghi rõ lý do tạm ứng.'; end if;
    if exists (select 1 from erp_doc where co = p_co and type = 'ADV' and data->>'emp' = u.username and status in ('pending','approved','paid')) then
      raise exception 'Bạn còn khoản tạm ứng chưa quyết toán. Quyết toán khoản cũ trước khi đề nghị tạm ứng tiếp.'; end if;
    b := b || jsonb_build_object('amount', amt, 'emp', u.username, 'empName', u.full_name);
    st := 'pending';

  elsif p_type = 'ADS' then
    src := erp_doc_data(p_co, b->>'adv');
    if src is null or src->>'type' <> 'ADV' or src->>'status' <> 'paid' then raise exception 'Khoản tạm ứng chưa được chi hoặc đã quyết toán.'; end if;
    if src->>'emp' <> u.username and not u.is_admin then raise exception 'Chỉ người nhận tạm ứng được lập giấy thanh toán tạm ứng.'; end if;
    if exists (select 1 from erp_doc where co = p_co and type = 'ADS' and status in ('pending','approved') and data->>'adv' = b->>'adv') then
      raise exception 'Khoản tạm ứng này đang có giấy thanh toán chờ duyệt.'; end if;
    for it in select * from jsonb_array_elements(coalesce(b->'lines','[]')) loop
      a := erp_manual_line(p_co, it->>'a', it->>'cc', false);
      if not erp_acc_ok('ADS', a.code) then raise exception 'TK % không dùng cho thanh toán tạm ứng (chỉ chi phí 6xx, 811, 242, thuế GTGT được khấu trừ 1331).', a.code; end if;
      q := round(coalesce(erp_num(it,'amount'),0)); if q <= 0 then raise exception 'Số tiền từng khoản chi phải lớn hơn 0.'; end if;
      if coalesce(trim(it->>'memo'),'') = '' then raise exception 'Ghi nội dung và số chứng từ gốc của từng khoản chi.'; end if;
      v_exp := v_exp + q;
      items := items || jsonb_strip_nulls(jsonb_build_object('a',a.code,'amount',q,'cc',nullif(it->>'cc',''),'memo',trim(it->>'memo')));
    end loop;
    if jsonb_array_length(items) = 0 then raise exception 'Chưa có khoản chi nào.'; end if;
    b := b || jsonb_build_object('lines',items,'expTotal',v_exp,'advAmount',erp_num(src,'amount'),'ret',erp_num(src,'amount') - v_exp,
           'emp',src->>'emp','empName',src->>'empName');
    st := 'pending';
  end if;

  select coalesce(max(seq),0) + 1 into s from erp_doc where co = p_co and type = p_type;
  pre := case p_type when 'PR' then '100000' when 'PO' then '450000' when 'GR' then '500000' when 'IV' then '510000'
                     when 'PAY' then '150000' when 'SO' then '000010' when 'DL' then '800000' when 'BI' then '900000'
                     when 'RC' then '140000' when 'JE' then '010000' when 'CJ' then '030000' when 'CNT' then '040000'
                     when 'ADV' then '060000' when 'ADS' then '070000' end;
  v_id := p_type || lpad(s::text, 5, '0');
  v_no := pre || lpad(s::text, 4, '0');
  if p_type = 'BI' then b := b || jsonb_build_object('invNo', lpad(s::text, 8, '0')); end if;
  if p_type in ('GR','IV','DL','BI') then
    posted := erp_post(p_co, v_id, p_type, d, u.id, je, coalesce(b->>'reason',''));
    b := b || jsonb_build_object('je', posted->'lines', 'jeNo', posted->>'je', 'pdate', posted->>'date');
    if p_type = 'GR' then
      for it in select * from jsonb_array_elements(items) loop
        perform erp_val_in(p_co, it->>'mat', (it->>'qty')::numeric, (it->>'qty')::numeric * (it->>'price')::numeric);
      end loop;
    elsif p_type = 'IV' then
      for it in select * from jsonb_array_elements(items) loop
        diff := ((it->>'price')::numeric - (it->>'poPrice')::numeric) * (it->>'qty')::numeric;
        if diff <> 0 then perform erp_val_in(p_co, it->>'mat', 0, diff); end if;
      end loop;
    end if;
  end if;
  b := b || jsonb_build_object('type',p_type,'seq',s,'no',v_no,'at',ts,'by',u.id::text,'role',r,'status',st,
       'hist', jsonb_build_array(jsonb_build_object('at',ts,'by',u.id::text,'role',r,'act','create','note',note)));
  insert into erp_doc(co,id,type,seq,status,data) values (p_co, v_id, p_type, s, st, b);
  return jsonb_build_object('id', v_id, 'no', v_no, 'status', st, 'je', b->>'jeNo');
end $$;

-- ---------- Phê duyệt chứng từ (thay bản 004) ----------
create or replace function erp_doc_decide(p_token text, p_co text, p_id text, p_ok boolean, p_note text, p_act_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u erp_user; r text; d erp_doc; ns text; nd jsonb; ts text := erp_iso(); acc text; amt numeric; bal numeric; posted jsonb; pa erp_partner;
        clr text; lines jsonb; ins jsonb; p2 jsonb; it jsonb; wd date; src jsonb; rd text; bankClear boolean;
begin
  u := erp_auth(p_token);
  if u.is_admin then
    r := coalesce(nullif(p_act_role,''), 'GV');
    if r not in ('GV','KTT') then raise exception 'Hãy chọn vai trò Giảng viên hoặc Kế toán trưởng để phê duyệt.'; end if;
  else
    if not erp_can_approve(u) then raise exception 'Chỉ Kế toán trưởng hoặc người được giao quyền phê duyệt mới được duyệt chứng từ.'; end if;
    if p_co is distinct from u.co then raise exception 'Không được phê duyệt chứng từ của công ty khác.'; end if;
    r := case when erp_can(erp_roles_of(u), 'SBWP', 'A') then 'KTT' else 'T:AP' end;
  end if;
  perform pg_advisory_xact_lock(hashtext('erp:doc:' || p_co));
  select * into d from erp_doc where co = p_co and id = p_id for update;
  if not found then raise exception 'Không tìm thấy chứng từ.'; end if;
  if not ((d.type in ('PR','PO','PAY','RC','JE','CJ','CNT','ADV','ADS') and d.status = 'pending') or (d.type in ('IV','SO') and d.status = 'blocked')) then
    raise exception 'Chứng từ không còn ở trạng thái chờ xử lý.';
  end if;
  if d.data->>'by' = u.id::text and not u.is_admin
     and not coalesce((select (v->>'selfApprove')::boolean from erp_cfg where k = 'main'), false) then
    raise exception 'Vi phạm bất kiêm nhiệm: không được phê duyệt chứng từ do chính mình lập.';
  end if;
  -- Ngoại lệ tự duyệt (kiêm nhiệm hoặc giảng viên) phải có lý do (bất biến 6)
  if d.data->>'by' = u.id::text and p_ok and coalesce(trim(p_note),'') = '' then
    raise exception 'Tự duyệt chứng từ do chính mình lập phải ghi lý do (ngoại lệ kiêm nhiệm).'; end if;
  if not p_ok and coalesce(trim(p_note),'') = '' then raise exception 'Hãy ghi lý do từ chối.'; end if;

  nd := d.data; wd := erp_wdate(p_co);
  bankClear := coalesce((select (v->>'bankClear')::boolean from erp_cfg where k = 'main'), true);
  if not p_ok then
    ns := 'rejected';
    if d.type = 'IV' then raise exception 'Hóa đơn đã ghi sổ không hủy bằng từ chối. Gỡ khóa khi nhà cung cấp đã xác nhận giá, hoặc chờ hóa đơn điều chỉnh (P4).'; end if;
  elsif d.type in ('PAY','RC') then
    acc := d.data->>'acc'; amt := (d.data->>'amount')::numeric;
    if acc not in (erp_ad('CASH'), erp_ad('BANK')) then raise exception 'Tài khoản tiền không hợp lệ.'; end if;
    if d.type = 'PAY' then
      select * into pa from erp_partner where co = p_co and code = d.data->>'vendor';
      if not pa.active then raise exception 'Nhà cung cấp % đang bị khóa (XK02): không duyệt chi.', pa.code; end if;
    end if;
    if acc = erp_ad('CASH') then
      -- Tiền mặt: Kế toán trưởng duyệt, Thủ quỹ chi/thu thực tế rồi xác nhận mới ghi TK 111
      if d.type = 'PAY' and erp_balance(p_co, acc) < amt then
        raise exception 'Không đủ số dư TK % (còn % đồng).', acc, erp_fm(erp_balance(p_co, acc)); end if;
      ns := 'approved';
    elsif d.type = 'PAY' then
      -- Chi chuyển khoản: ghi Có TK 113 đến khi sao kê xác nhận ngân hàng đã chuyển (cách tài khoản trung gian kiểu SAP – xem TIENDO P3)
      clr := case when bankClear then erp_ad('BANK_CLR') else acc end;
      bal := erp_balance(p_co, acc) + case when clr <> acc then least(erp_balance(p_co, clr), 0) else 0 end;
      if bal < amt then raise exception 'Không đủ số dư TK % (còn % đồng, đã trừ các khoản chi đang chuyển).', acc, erp_fm(bal); end if;
      nd := nd || jsonb_build_object('bankAcc', pa.bank_acc, 'bankName', pa.bank_name);
      posted := erp_post(p_co, d.id, 'PAY', null, u.id,
        jsonb_build_array(jsonb_build_object('a',erp_ad('AP'),'dr',amt,'p',d.data->>'vendor'), jsonb_build_object('a',clr,'cr',amt)), '');
      ns := 'posted';
      nd := nd || jsonb_build_object('je', posted->'lines', 'jeNo', posted->>'je', 'pdate', posted->>'date', 'postDate', ts);
      if clr <> acc then nd := nd || jsonb_build_object('clr', clr); end if;
    else
      -- Thu chuyển khoản đã có giấy báo Có: ghi thẳng Nợ 112; sao kê phát hành dòng đã khớp
      posted := erp_post(p_co, d.id, 'RC', null, u.id,
        jsonb_build_array(jsonb_build_object('a',acc,'dr',amt), jsonb_build_object('a',erp_ad('AR'),'cr',amt,'p',d.data->>'cust')), '');
      ns := 'posted';
      nd := nd || jsonb_build_object('je', posted->'lines', 'jeNo', posted->>'je', 'pdate', posted->>'date', 'postDate', ts);
      if bankClear then nd := nd || jsonb_build_object('bankDirect', true); end if;
    end if;
  elsif d.type = 'JE' then
    if d.data->>'kind' = 'acc' and to_char(wd,'YYYY-MM') <> left(d.data->>'date',7) then
      raise exception 'Bút toán trích trước lập cho kỳ %, nhưng ngày làm việc đã sang kỳ %: nếu duyệt, chi phí sẽ không nằm đúng kỳ. Từ chối và lập lại, hoặc nhờ giảng viên lùi ngày làm việc.',
        to_char(erp_date(d.data->>'date'),'MM/YYYY'), to_char(wd,'MM/YYYY'); end if;
    posted := erp_post(p_co, d.id, 'JE', null, u.id, d.data->'lines', d.data->>'memo');
    ns := 'posted';
    nd := nd || jsonb_build_object('je', posted->'lines', 'jeNo', posted->>'je', 'pdate', posted->>'date');
    if d.data->>'kind' = 'rev' then
      update erp_doc set data = data || jsonb_build_object('revBy', d.id, 'revNo', d.data->>'no'), updated_at = clock_timestamp()
       where co = p_co and id = d.data->>'revOf';
      -- Đảo chứng từ ghi sổ theo sao kê: mở lại dòng sao kê để xử lý lại
      update erp_bank_line set status = 'open', bs_doc = null, updated_at = clock_timestamp()
       where co = p_co and bs_doc = d.data->>'revOf';
    elsif d.data->>'kind' = 'acc' then
      rd := to_char(date_trunc('month', wd) + interval '1 month','YYYY-MM-DD');
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('a',x->>'a','dr',x->'cr','cr',x->'dr','cc',x->>'cc','memo',x->>'memo')))
        into lines from jsonb_array_elements(posted->'lines') x;
      ins := erp_doc_ins(p_co, 'JE', 'posted', jsonb_build_object('kind','rev','auto',true,'revOf',d.id,'revNo',d.data->>'no',
               'date', rd, 'memo', 'Tự đảo bút toán trích trước ' || (d.data->>'no'), 'lines', lines,
               'amount', d.data->'amount', 'at', ts, 'by', u.id::text, 'role', r,
               'hist', jsonb_build_array(jsonb_build_object('at',ts,'by',u.id::text,'role',r,'act','create','note','Tự đảo đầu kỳ sau (FBS1)'))));
      perform set_config('erp.fixed_date', 'on', true);
      p2 := erp_post(p_co, ins->>'id', 'JE', erp_date(rd), u.id, lines, 'Tự đảo bút toán trích trước ' || (d.data->>'no'));
      perform set_config('erp.fixed_date', '', true);
      update erp_doc set data = data || jsonb_build_object('je', p2->'lines', 'jeNo', p2->>'je', 'pdate', p2->>'date'), updated_at = clock_timestamp()
       where co = p_co and id = ins->>'id';
      nd := nd || jsonb_build_object('revBy', ins->>'id', 'revNo', ins->>'no', 'revDate', rd);
    end if;
  elsif d.type = 'CJ' then
    amt := (d.data->>'amount')::numeric;
    if d.data->>'dir' in ('out','dep') and erp_balance(p_co, erp_ad('CASH')) < amt then
      raise exception 'Không đủ tồn quỹ tiền mặt (còn % đồng). Tồn quỹ không được âm.', erp_fm(erp_balance(p_co, erp_ad('CASH'))); end if;
    if d.data->>'dir' = 'wd' and erp_balance(p_co, erp_ad('BANK')) + least(erp_balance(p_co, erp_ad('BANK_CLR')),0) < amt then
      raise exception 'Không đủ số dư tiền gửi để rút.'; end if;
    ns := 'approved';
  elsif d.type = 'CNT' then
    amt := (d.data->>'diff')::numeric;
    lines := case when amt < 0
      then jsonb_build_array(jsonb_build_object('a',erp_ad('CASH_SHORT'),'dr',-amt), jsonb_build_object('a',erp_ad('CASH'),'cr',-amt))
      else jsonb_build_array(jsonb_build_object('a',erp_ad('CASH'),'dr',amt), jsonb_build_object('a',erp_ad('CASH_OVER'),'cr',amt)) end;
    posted := erp_post(p_co, d.id, 'CNT', null, u.id, lines, 'Chênh lệch kiểm quỹ: ' || coalesce(d.data->>'reason',''));
    ns := 'posted';
    nd := nd || jsonb_build_object('je', posted->'lines', 'jeNo', posted->>'je', 'pdate', posted->>'date');
  elsif d.type = 'ADS' then
    amt := (d.data->>'ret')::numeric;
    if amt <> 0 then
      if amt < 0 and erp_balance(p_co, erp_ad('CASH')) < -amt then
        raise exception 'Không đủ tồn quỹ để chi bổ sung phần chi vượt tạm ứng (còn % đồng).', erp_fm(erp_balance(p_co, erp_ad('CASH'))); end if;
      ns := 'approved';   -- có thu/chi tiền mặt: chờ Thủ quỹ xác nhận
    else
      posted := erp_post(p_co, d.id, 'ADS', null, u.id, erp_ads_lines(d.data), 'Quyết toán tạm ứng ' || coalesce(d.data->>'adv',''));
      ns := 'posted';
      nd := nd || jsonb_build_object('je', posted->'lines', 'jeNo', posted->>'je', 'pdate', posted->>'date');
      update erp_doc set status = 'settled', updated_at = clock_timestamp(),
        data = data || jsonb_build_object('status','settled','setBy',d.id,'setNo',d.data->>'no') where co = p_co and id = d.data->>'adv';
    end if;
  elsif d.type = 'IV' then ns := 'posted';
  else ns := 'approved';
  end if;
  nd := nd || jsonb_build_object('status', ns, 'decBy', u.id::text, 'decAt', ts,
        'hist', coalesce(nd->'hist','[]'::jsonb) || jsonb_build_array(jsonb_build_object('at',ts,'by',u.id::text,'role',r,
                 'act', case when p_ok then 'approve' else 'reject' end, 'note', coalesce(p_note,''),
                 'self', d.data->>'by' = u.id::text)));
  update erp_doc set status = ns, data = nd, updated_at = clock_timestamp() where co = p_co and id = p_id;
  return jsonb_build_object('status', ns);
end $$;

-- ---------- Đồng bộ (thay bản 004) ----------
create or replace function erp_md_json(p_co text) returns jsonb language sql stable set search_path = public, extensions as $$
  select jsonb_build_object(
    'mats', coalesce((select jsonb_agg(jsonb_build_object('c',code,'n',name,'u',unit,'t',mtype,'acc',acc,'oq',open_qty,'oc',open_cost,
              'bp',buy_price,'sp',sell_price,'min',min_stock,'sloc',sloc,'pc',pc,'from',valid_from,'active',active) order by code) from erp_mat where co = p_co),'[]'),
    'partners', coalesce((select jsonb_agg(jsonb_build_object('c',code,'k',kind,'n',name,'mst',mst,'terms',terms,'lim',credit_lim,'f',price_factor,
              'addr',address,'bank',bank_acc,'bankName',bank_name,'active',active,'ok',confirmed) order by code) from erp_partner where co = p_co),'[]'),
    'prices', coalesce((select jsonb_agg(jsonb_build_object('v',vendor,'m',mat,'p',price,'from',valid_from) order by vendor, mat, valid_from) from erp_price where co = p_co),'[]'),
    'chg', coalesce((select jsonb_agg(jsonb_build_object('id',id,'obj',obj,'key',key,'f',field,'o',old_val,'n',new_val,'st',status,'by',by,'at',at,'dby',dec_by,'dat',dec_at,'note',note) order by id desc)
              from (select * from erp_md_change where co = p_co order by id desc limit 300) z),'[]'),
    'org', coalesce((select jsonb_agg(jsonb_build_object('k',kind,'c',code,'n',name,'p',parent,'note',note) order by kind, code) from erp_org where co = p_co),'[]'),
    'state', jsonb_build_object('wdate', to_char(erp_wdate(p_co),'YYYY-MM-DD')),
    'periods', coalesce((select jsonb_agg(jsonb_build_object('fy',fy,'per',period,'grp',grp,'by',by,'at',at) order by fy, period, grp) from erp_period_close where co = p_co),'[]'),
    'bank', coalesce((select jsonb_agg(jsonb_build_object('id',id,'vdate',vdate,'amt',amt,'descr',descr,'kind',kind,'ref',ref_doc,'st',status,'bs',bs_doc) order by vdate, id)
              from erp_bank_line where co = p_co),'[]'))
$$;

create or replace function erp_md_changed(p_co text, p_since timestamptz) returns boolean language sql stable set search_path = public, extensions as $$
  select p_since is null
      or exists (select 1 from erp_mat where co = p_co and updated_at > p_since - interval '15 seconds')
      or exists (select 1 from erp_partner where co = p_co and updated_at > p_since - interval '15 seconds')
      or exists (select 1 from erp_price where co = p_co and updated_at > p_since - interval '15 seconds')
      or exists (select 1 from erp_md_change where co = p_co and greatest(at, coalesce(dec_at, at)) > p_since - interval '15 seconds')
      or exists (select 1 from erp_co_state where co = p_co and updated_at > p_since - interval '15 seconds')
      or exists (select 1 from erp_bank_line where co = p_co and updated_at > p_since - interval '15 seconds')
$$;

create or replace function erp_sync(p_token text, p_co text, p_since timestamptz) returns jsonb language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user; v_co text := p_co; v_docs jsonb; v_users jsonb; v_now timestamptz := clock_timestamp(); v_acc jsonb; v_md jsonb := '{}'; c text; v_auth jsonb;
begin
  u := erp_auth(p_token);
  if not u.is_admin then v_co := u.co; elsif v_co is null or v_co = '' then v_co := '*'; end if;
  if v_co is null then
    v_docs := '[]'::jsonb;
  else
    select coalesce(jsonb_agg(jsonb_build_object('co',d.co,'id',d.id,'data',d.data)), '[]'::jsonb) into v_docs
      from erp_doc d
     where (v_co = '*' or d.co = v_co)
       and (p_since is null or d.updated_at > p_since - interval '15 seconds');
    foreach c in array erp_cos() loop
      if (v_co = '*' or c = v_co) and erp_md_changed(c, p_since) then v_md := v_md || jsonb_build_object(c, erp_md_json(c)); end if;
    end loop;
  end if;
  if u.is_admin then
    select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'username',x.username,'full_name',x.full_name,'is_admin',x.is_admin,
       'co',x.co,'role',x.role,'extra',coalesce(to_jsonb(x.extra),'[]'::jsonb),'grp',x.grp,'must_change',x.must_change,'last_login',x.last_login) order by x.username), '[]'::jsonb)
      into v_users from erp_user x;
  else
    select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'full_name',x.full_name,'is_admin',x.is_admin,'co',x.co,'role',x.role,'extra',coalesce(to_jsonb(x.extra),'[]'::jsonb))), '[]'::jsonb)
      into v_users from erp_user x where x.is_admin or x.co = u.co;
  end if;
  if p_since is null then
    select jsonb_object_agg(code, jsonb_build_object('n',name,'k',kind,'r',recon,'ph',from_phase,'man',manual,'cc',cc_req)) into v_acc from erp_acct where active;
    v_auth := jsonb_build_object(
      'roles', (select jsonb_agg(jsonb_build_object('c',code,'n',name,'dept',dept,'d',descr,'ph',phase) order by sort) from erp_role),
      'perms', (select jsonb_object_agg(role, tcs) from (select role, jsonb_agg(jsonb_build_object('tc',tc,'a',act)) tcs from erp_role_perm group by role) z),
      'packs', (select jsonb_agg(jsonb_build_object('c',code,'n',name,'seats',seats,'note',note) order by sort) from erp_role_pack),
      'conflict', (select jsonb_object_agg(a.code || '|' || b.code, jsonb_build_object('s', erp_conflict(a.code, b.code),
                     'w', coalesce((select risk from erp_role_conflict x where (x.a,x.b) in ((a.code,b.code),(b.code,a.code)) limit 1),
                                   case when 'KSNB' in (a.code,b.code) then 'Kiểm toán nội bộ phải độc lập với đối tượng được kiểm tra'
                                        when 'KTT' in (a.code,b.code) then 'Vừa lập vừa phê duyệt' else '' end)))
                     from erp_role a join erp_role b on a.code < b.code where erp_conflict(a.code, b.code) > 0));
  end if;
  return jsonb_build_object(
    'now', v_now,
    'me', erp_user_json(u),
    'cfg', (select v from erp_cfg where k = 'main'),
    'epochs', (select v from erp_cfg where k = 'epoch'),
    'users', v_users,
    'accts', v_acc,
    'auth', v_auth,
    'md', v_md,
    'adm', case when u.is_admin then (select jsonb_object_agg(s.co, jsonb_build_object('cash', s.cash_count, 'wdate', to_char(s.wdate,'YYYY-MM-DD'),
             'presets', coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'vdate',p.vdate,'kind',p.kind,'amt',p.amt,'descr',p.descr,'issued',p.issued) order by p.vdate)
                                  from erp_bank_preset p where p.co = s.co),'[]'))) from erp_co_state s) end,
    'docs', v_docs);
end $$;

-- ---------- Quyền gọi hàm ----------
do $$
declare f text;
begin
  foreach f in array array['erp_wdate(text)','erp_acct_grp(text)','erp_period_closed(text,date,text)','erp_post(text,text,text,date,uuid,jsonb,text)',
    'erp_doc_ins(text,text,text,jsonb)','erp_manual_line(text,text,text,boolean)','erp_bank_seed(text)','erp_bank_issue(text)',
    'erp_purge_co(text)','erp_type_role(text)','erp_type_tc(text)','erp_md_json(text)','erp_md_changed(text,timestamptz)',
    'erp_acc_ok(text,text)','erp_bs_alloc(text,text)','erp_kid_amt(text,text,text,text)','erp_ads_lines(jsonb)'] loop
    execute 'revoke execute on function ' || f || ' from public';
    if exists (select 1 from pg_roles where rolname='anon') then execute 'revoke execute on function ' || f || ' from anon'; end if;
    if exists (select 1 from pg_roles where rolname='authenticated') then execute 'revoke execute on function ' || f || ' from authenticated'; end if;
  end loop;
  foreach f in array array['erp_doc_create(text,text,text,jsonb,text,text)','erp_doc_decide(text,text,text,boolean,text,text)',
    'erp_sync(text,text,timestamptz)','erp_admin_set_state(text,text,jsonb)','erp_period_set(text,text,integer,integer,text,boolean,text)',
    'erp_bank_match(text,text,text,jsonb,text)','erp_bank_refresh(text,text)','erp_admin_set_cfg(text,jsonb)',
    'erp_cash_confirm(text,text,text,text)','erp_susp_clear(text,text,text,text,numeric,text)'] loop
    execute 'revoke execute on function ' || f || ' from public';
    if exists (select 1 from pg_roles where rolname='anon') then execute 'grant execute on function ' || f || ' to anon'; end if;
    if exists (select 1 from pg_roles where rolname='authenticated') then execute 'grant execute on function ' || f || ' to authenticated'; end if;
  end loop;
end $$;
alter function erp_wdate(text) set search_path = public, extensions;
