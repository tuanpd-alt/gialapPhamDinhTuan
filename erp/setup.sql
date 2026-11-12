-- =====================================================================
-- ERP Lab – cài đặt/cập nhật cơ sở dữ liệu trên Supabase (TỆP SINH TỰ ĐỘNG từ erp/sql/*.sql)
-- Cách dùng: Supabase > SQL Editor > New query > dán toàn bộ > Run. Chạy lại an toàn, không xóa dữ liệu.
-- TRƯỚC KHI CHẠY: sửa mật khẩu giảng viên ở dòng cuối cùng.
-- =====================================================================

-- >>>>>>>>>> sql/001_base.sql
-- =====================================================================
-- ERP Lab HTTTKT – cài đặt cơ sở dữ liệu trên Supabase
-- Cách dùng: Supabase > SQL Editor > New query > dán toàn bộ file này > Run.
-- Chạy lại nhiều lần vẫn an toàn (không xóa dữ liệu đã có).
-- TRƯỚC KHI CHẠY: sửa mật khẩu giảng viên ở dòng cuối cùng của file.
-- =====================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------- Bảng ----------
create table if not exists erp_user(
  id uuid primary key default gen_random_uuid(),
  username text unique not null,
  full_name text not null,
  pass_hash text not null,
  is_admin boolean not null default false,
  co text,
  role text,
  grp int,
  must_change boolean not null default true,
  created_at timestamptz not null default now(),
  last_login timestamptz
);
create table if not exists erp_session(
  token uuid primary key default gen_random_uuid(),
  user_id uuid not null references erp_user(id) on delete cascade,
  expires_at timestamptz not null
);
create table if not exists erp_doc(
  co text not null,
  id text not null,
  type text not null,
  seq int not null,
  status text not null,
  data jsonb not null,
  updated_at timestamptz not null default clock_timestamp(),
  primary key(co,id)
);
create index if not exists erp_doc_upd on erp_doc(co, updated_at);
-- Kiêm nhiệm / giao quyền: mã vai trò (KHO, MH, KD, KT, KTT) hoặc quyền lẻ T:<loại chứng từ> / T:AP (phê duyệt)
alter table erp_user add column if not exists extra text[] not null default '{}';
create table if not exists erp_cfg(k text primary key, v jsonb not null);
insert into erp_cfg values ('main','{"tol":5,"poAuto":0,"credit":true,"selfApprove":false}') on conflict do nothing;
insert into erp_cfg values ('epoch','{}') on conflict do nothing;

-- Không ai đọc/ghi bảng trực tiếp qua API; mọi truy cập đi qua các hàm bên dưới.
alter table erp_user enable row level security;
alter table erp_session enable row level security;
alter table erp_doc enable row level security;
alter table erp_cfg enable row level security;
do $$ begin
  if exists (select 1 from pg_roles where rolname='anon') then
    execute 'revoke all on erp_user, erp_session, erp_doc, erp_cfg from anon';
  end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then
    execute 'revoke all on erp_user, erp_session, erp_doc, erp_cfg from authenticated';
  end if;
end $$;

-- ---------- Hàm nội bộ ----------
create or replace function erp_iso() returns text language sql volatile as
$$ select to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') $$;

create or replace function erp_cos() returns text[] language sql immutable as
$$ select array['C01','C02','C03','C04','C05','C06','C07','C08'] $$;

create or replace function erp_genpw() returns text language plpgsql volatile
set search_path = public, extensions as $$
declare a text := 'abcdefghjkmnpqrstuvwxyz23456789'; b bytea := gen_random_bytes(8); r text := ''; i int;
begin
  for i in 0..7 loop r := r || substr(a, (get_byte(b,i) % length(a)) + 1, 1); end loop;
  return r;
end $$;

create or replace function erp_auth(p_token text) returns erp_user language plpgsql
security definer set search_path = public, extensions as $$
declare t uuid; u erp_user;
begin
  begin t := p_token::uuid; exception when others then
    raise exception 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.' using errcode = '28000'; end;
  select u2.* into u from erp_session s join erp_user u2 on u2.id = s.user_id
   where s.token = t and s.expires_at > now();
  if not found then raise exception 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.' using errcode = '28000'; end if;
  return u;
end $$;

create or replace function erp_require_admin(p_token text) returns erp_user language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user;
begin
  u := erp_auth(p_token);
  if not u.is_admin then raise exception 'Chức năng này chỉ dành cho giảng viên.'; end if;
  return u;
end $$;

-- Vai trò dùng để lập loại chứng từ: vai trò chính, vai trò kiêm nhiệm, hoặc quyền lẻ được giao
create or replace function erp_type_role(p_type text) returns text language sql immutable as $$
  select case p_type when 'PR' then 'KHO' when 'GR' then 'KHO' when 'DL' then 'KHO' when 'PO' then 'MH' when 'SO' then 'KD'
                     when 'IV' then 'KT' when 'PAY' then 'KT' when 'BI' then 'KT' when 'RC' then 'KT' end
$$;
create or replace function erp_role_for(u erp_user, p_type text) returns text language sql stable as $$
  select case
    when u.role = erp_type_role(p_type) then u.role
    when erp_type_role(p_type) = any(coalesce(u.extra,'{}')) then erp_type_role(p_type)
    when ('T:' || p_type) = any(coalesce(u.extra,'{}')) then erp_type_role(p_type)
  end
$$;
create or replace function erp_can_approve(u erp_user) returns boolean language sql stable as $$
  select u.role = 'KTT' or 'KTT' = any(coalesce(u.extra,'{}')) or 'T:AP' = any(coalesce(u.extra,'{}'))
$$;

create or replace function erp_balance(p_co text, p_acc text) returns numeric language sql stable
set search_path = public, extensions as $$
  select (case p_acc when '1111' then 200000000 when '1121' then 3000000000 else 0 end)::numeric
       + coalesce((select sum(coalesce((j->>'dr')::numeric,0) - coalesce((j->>'cr')::numeric,0))
           from erp_doc d, jsonb_array_elements(case when jsonb_typeof(d.data->'je')='array' then d.data->'je' else '[]'::jsonb end) j
          where d.co = p_co and d.status <> 'rejected' and j->>'a' = p_acc), 0)
$$;

create or replace function erp_user_json(u erp_user) returns jsonb language sql stable as $$
  select jsonb_build_object('id',u.id,'username',u.username,'full_name',u.full_name,'is_admin',u.is_admin,
    'co',u.co,'role',u.role,'extra',coalesce(to_jsonb(u.extra),'[]'::jsonb),'grp',u.grp,'must_change',u.must_change)
$$;

-- Chỉ chạy được trong SQL Editor (không mở cho trình duyệt)
create or replace function erp_create_admin(p_username text, p_password text, p_full_name text)
returns text language plpgsql security definer set search_path = public, extensions as $$
begin
  if length(coalesce(p_password,'')) < 8 then raise exception 'Mật khẩu giảng viên cần ít nhất 8 ký tự.'; end if;
  insert into erp_user(username, full_name, pass_hash, is_admin, must_change)
  values (lower(trim(p_username)), p_full_name, crypt(p_password, gen_salt('bf', 8)), true, false)
  on conflict (username) do update set pass_hash = excluded.pass_hash, is_admin = true, full_name = excluded.full_name, must_change = false;
  return 'Đã tạo/cập nhật tài khoản giảng viên ' || lower(trim(p_username));
end $$;

-- ---------- API cho trình duyệt ----------
create or replace function erp_login(p_username text, p_password text) returns jsonb language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user; t uuid;
begin
  select * into u from erp_user where username = lower(trim(p_username));
  if not found or u.pass_hash <> crypt(coalesce(p_password,''), u.pass_hash) then
    perform pg_sleep(0.4);
    raise exception 'Sai MSSV hoặc mật khẩu.';
  end if;
  delete from erp_session where expires_at < now();
  insert into erp_session(user_id, expires_at) values (u.id, now() + interval '12 hours') returning token into t;
  update erp_user set last_login = now() where id = u.id;
  return jsonb_build_object('token', t);
end $$;

create or replace function erp_logout(p_token text) returns void language plpgsql
security definer set search_path = public, extensions as $$
begin
  begin delete from erp_session where token = p_token::uuid; exception when others then null; end;
end $$;

create or replace function erp_change_password(p_token text, p_old text, p_new text) returns void language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user;
begin
  u := erp_auth(p_token);
  if u.pass_hash <> crypt(coalesce(p_old,''), u.pass_hash) then raise exception 'Mật khẩu hiện tại không đúng.'; end if;
  if length(coalesce(p_new,'')) < 6 then raise exception 'Mật khẩu mới cần ít nhất 6 ký tự.'; end if;
  if p_new = p_old then raise exception 'Mật khẩu mới phải khác mật khẩu cũ.'; end if;
  update erp_user set pass_hash = crypt(p_new, gen_salt('bf', 8)), must_change = false where id = u.id;
end $$;

create or replace function erp_sync(p_token text, p_co text, p_since timestamptz) returns jsonb language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user; v_co text := p_co; v_docs jsonb; v_users jsonb; v_now timestamptz := clock_timestamp();
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
  end if;
  if u.is_admin then
    select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'username',x.username,'full_name',x.full_name,'is_admin',x.is_admin,
       'co',x.co,'role',x.role,'extra',coalesce(to_jsonb(x.extra),'[]'::jsonb),'grp',x.grp,'must_change',x.must_change,'last_login',x.last_login) order by x.username), '[]'::jsonb)
      into v_users from erp_user x;
  else
    select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'full_name',x.full_name,'is_admin',x.is_admin,'co',x.co,'role',x.role,'extra',coalesce(to_jsonb(x.extra),'[]'::jsonb))), '[]'::jsonb)
      into v_users from erp_user x where x.is_admin or x.co = u.co;
  end if;
  return jsonb_build_object(
    'now', v_now,
    'me', erp_user_json(u),
    'cfg', (select v from erp_cfg where k = 'main'),
    'epochs', (select v from erp_cfg where k = 'epoch'),
    'users', v_users,
    'docs', v_docs);
end $$;

create or replace function erp_doc_create(p_token text, p_co text, p_type text, p_body jsonb, p_note text, p_act_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  u erp_user; r text; st text; s int; v_id text; v_no text; ts text := erp_iso();
  pre text; allowed text[]; ref_fld text; ref_ok text[]; ref_st text; po_auto numeric; b jsonb := p_body;
begin
  u := erp_auth(p_token);
  if u.is_admin then
    r := coalesce(nullif(p_act_role,''), 'GV');
    if r not in ('GV','KHO','MH','KD','KT','KTT') then raise exception 'Vai trò không hợp lệ.'; end if;
  else
    if u.co is null or u.role is null then raise exception 'Bạn chưa được giảng viên phân công vào công ty.'; end if;
    if p_co is distinct from u.co then raise exception 'Không được ghi chứng từ cho công ty khác.'; end if;
    r := u.role;
  end if;
  if not (p_co = any(erp_cos())) then raise exception 'Mã công ty không hợp lệ.'; end if;
  if jsonb_typeof(b) <> 'object' then raise exception 'Dữ liệu chứng từ không hợp lệ.'; end if;

  allowed := case p_type when 'PR' then array['KHO'] when 'GR' then array['KHO'] when 'DL' then array['KHO']
    when 'PO' then array['MH'] when 'SO' then array['KD']
    when 'IV' then array['KT'] when 'PAY' then array['KT'] when 'BI' then array['KT'] when 'RC' then array['KT'] end;
  if allowed is null then raise exception 'Loại chứng từ % không tồn tại.', p_type; end if;
  if u.is_admin then
    if r <> 'GV' and not (r = any(allowed)) then
      raise exception 'Vai trò % không được lập loại chứng từ này (SU53).', r;
    end if;
  else
    r := erp_role_for(u, p_type);
    if r is null then
      raise exception 'Bạn chưa được giao quyền lập loại chứng từ này (SU53). Nhờ giảng viên giao kiêm nhiệm nếu nhóm thiếu người.';
    end if;
  end if;

  st := b->>'status';
  if not ((p_type = 'PR' and st = 'pending') or (p_type = 'PO' and st in ('pending','approved'))
       or (p_type in ('GR','DL','BI') and st = 'posted') or (p_type = 'IV' and st in ('posted','blocked'))
       or (p_type in ('PAY','RC') and st = 'pending') or (p_type = 'SO' and st in ('approved','blocked'))) then
    raise exception 'Trạng thái ban đầu không hợp lệ.';
  end if;
  if p_type = 'PO' and st = 'approved' then
    select coalesce((v->>'poAuto')::numeric,0) into po_auto from erp_cfg where k = 'main';
    if not (po_auto > 0 and coalesce((b->>'total')::numeric, 0) <= po_auto) then
      raise exception 'Đơn mua này phải được Kế toán trưởng phê duyệt.';
    end if;
  end if;
  if p_type in ('PR','PO','SO','PAY','RC') then b := b - 'je'; end if;

  ref_fld := case p_type when 'PO' then 'pr' when 'GR' then 'po' when 'IV' then 'po' when 'PAY' then 'iv'
                         when 'DL' then 'so' when 'BI' then 'dl' when 'RC' then 'bi' end;
  ref_ok := case p_type when 'PO' then array['approved'] when 'GR' then array['approved'] when 'IV' then array['approved']
                        when 'PAY' then array['posted'] when 'DL' then array['approved'] when 'BI' then array['posted']
                        when 'RC' then array['posted'] end;
  if ref_fld is not null then
    select status into ref_st from erp_doc where co = p_co and id = b->>ref_fld;
    if ref_st is null or not (ref_st = any(ref_ok)) then
      raise exception 'Chứng từ gốc không hợp lệ hoặc chưa được duyệt/ghi sổ.';
    end if;
  end if;

  perform pg_advisory_xact_lock(hashtext('erp:' || p_co || ':' || p_type));
  if p_type = 'PO' and exists (select 1 from erp_doc where co = p_co and type = 'PO' and status <> 'rejected' and data->>'pr' = b->>'pr') then
    raise exception 'Đề nghị mua này đã được lập đơn mua.';
  end if;
  if p_type = 'BI' and exists (select 1 from erp_doc where co = p_co and type = 'BI' and data->>'dl' = b->>'dl') then
    raise exception 'Phiếu xuất này đã được lập hóa đơn.';
  end if;

  select coalesce(max(seq),0) + 1 into s from erp_doc where co = p_co and type = p_type;
  pre := case p_type when 'PR' then '100000' when 'PO' then '450000' when 'GR' then '500000' when 'IV' then '510000'
                     when 'PAY' then '150000' when 'SO' then '000010' when 'DL' then '800000' when 'BI' then '900000'
                     when 'RC' then '140000' end;
  v_id := p_type || lpad(s::text, 5, '0');
  v_no := pre || lpad(s::text, 4, '0');
  if p_type = 'BI' then b := b || jsonb_build_object('invNo', lpad(s::text, 8, '0')); end if;
  b := b || jsonb_build_object('type',p_type,'seq',s,'no',v_no,'at',ts,'by',u.id::text,'role',r,
       'hist', jsonb_build_array(jsonb_build_object('at',ts,'by',u.id::text,'role',r,'act','create','note',coalesce(p_note,''))));
  insert into erp_doc(co,id,type,seq,status,data) values (p_co, v_id, p_type, s, st, b);
  return jsonb_build_object('id', v_id, 'no', v_no);
end $$;

create or replace function erp_doc_decide(p_token text, p_co text, p_id text, p_ok boolean, p_note text, p_act_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u erp_user; r text; d erp_doc; ns text; nd jsonb; ts text := erp_iso(); acc text; amt numeric; bal numeric;
begin
  u := erp_auth(p_token);
  if u.is_admin then
    r := coalesce(nullif(p_act_role,''), 'GV');
    if r not in ('GV','KTT') then raise exception 'Hãy chọn vai trò Giảng viên hoặc Kế toán trưởng để phê duyệt.'; end if;
  else
    if not erp_can_approve(u) then raise exception 'Chỉ Kế toán trưởng hoặc người được giao quyền phê duyệt mới được duyệt chứng từ.'; end if;
    if p_co is distinct from u.co then raise exception 'Không được phê duyệt chứng từ của công ty khác.'; end if;
    r := 'KTT';
  end if;
  select * into d from erp_doc where co = p_co and id = p_id for update;
  if not found then raise exception 'Không tìm thấy chứng từ.'; end if;
  if not ((d.type in ('PR','PO','PAY','RC') and d.status = 'pending') or (d.type in ('IV','SO') and d.status = 'blocked')) then
    raise exception 'Chứng từ không còn ở trạng thái chờ xử lý.';
  end if;
  if d.data->>'by' = u.id::text and not u.is_admin
     and not coalesce((select (v->>'selfApprove')::boolean from erp_cfg where k = 'main'), false) then
    raise exception 'Vi phạm bất kiêm nhiệm: không được phê duyệt chứng từ do chính mình lập.';
  end if;
  if not p_ok and coalesce(trim(p_note),'') = '' then raise exception 'Hãy ghi lý do từ chối.'; end if;

  nd := d.data;
  if not p_ok then
    ns := 'rejected';
  elsif d.type = 'PAY' then
    acc := d.data->>'acc'; amt := (d.data->>'amount')::numeric;
    if acc not in ('1111','1121') then raise exception 'Tài khoản chi không hợp lệ.'; end if;
    bal := erp_balance(p_co, acc);
    if bal < amt then raise exception 'Không đủ số dư TK % (còn % đồng).', acc, to_char(bal,'FM999G999G999G999'); end if;
    ns := 'posted';
    nd := nd || jsonb_build_object('je', jsonb_build_array(
            jsonb_build_object('a','331','dr',amt,'p',d.data->>'vendor'), jsonb_build_object('a',acc,'cr',amt)), 'postDate', ts);
  elsif d.type = 'RC' then
    acc := d.data->>'acc'; amt := (d.data->>'amount')::numeric;
    if acc not in ('1111','1121') then raise exception 'Tài khoản thu không hợp lệ.'; end if;
    ns := 'posted';
    nd := nd || jsonb_build_object('je', jsonb_build_array(
            jsonb_build_object('a',acc,'dr',amt), jsonb_build_object('a','131','cr',amt,'p',d.data->>'cust')), 'postDate', ts);
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

-- ---------- API cho giảng viên ----------
create or replace function erp_admin_import(p_token text, p_rows jsonb) returns jsonb language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user; e jsonb; m text; n text; g int; pw text; created jsonb := '[]'; skipped jsonb := '[]';
begin
  u := erp_require_admin(p_token);
  for e in select * from jsonb_array_elements(p_rows) loop
    m := lower(trim(e->>'mssv')); n := trim(e->>'name');
    begin g := nullif(trim(e->>'grp'),'')::int; exception when others then g := null; end;
    if m is null or m = '' or n is null or n = '' then continue; end if;
    if exists (select 1 from erp_user where username = m) then skipped := skipped || to_jsonb(m); continue; end if;
    pw := erp_genpw();
    insert into erp_user(username, full_name, pass_hash, grp) values (m, n, crypt(pw, gen_salt('bf', 8)), g);
    created := created || jsonb_build_object('mssv', m, 'name', n, 'password', pw);
  end loop;
  return jsonb_build_object('created', created, 'skipped', skipped);
end $$;

create or replace function erp_admin_reset_pw(p_token text, p_user uuid) returns jsonb language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user; pw text := erp_genpw(); x erp_user;
begin
  u := erp_require_admin(p_token);
  select * into x from erp_user where id = p_user;
  if not found then raise exception 'Không tìm thấy người dùng.'; end if;
  if x.is_admin then raise exception 'Đổi mật khẩu giảng viên bằng SQL Editor.'; end if;
  update erp_user set pass_hash = crypt(pw, gen_salt('bf', 8)), must_change = true where id = p_user;
  delete from erp_session where user_id = p_user;
  return jsonb_build_object('mssv', x.username, 'name', x.full_name, 'password', pw);
end $$;

create or replace function erp_admin_assign(p_token text, p_rows jsonb) returns int language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user; e jsonb; c text; r text; k int := 0; ex text[]; t text;
begin
  u := erp_require_admin(p_token);
  for e in select * from jsonb_array_elements(p_rows) loop
    c := nullif(e->>'co',''); r := nullif(e->>'role','');
    if c is not null and not (c = any(erp_cos())) then raise exception 'Mã công ty % không hợp lệ.', c; end if;
    if r is not null and r not in ('KHO','MH','KD','KT','KTT') then raise exception 'Vai trò % không hợp lệ.', r; end if;
    if e ? 'extra' and jsonb_typeof(e->'extra') = 'array' then
      select coalesce(array_agg(distinct x), '{}') into ex from jsonb_array_elements_text(e->'extra') x where x is distinct from r;
      foreach t in array ex loop
        if t not in ('KHO','MH','KD','KT','KTT','T:PR','T:PO','T:GR','T:IV','T:PAY','T:SO','T:DL','T:BI','T:RC','T:AP') then
          raise exception 'Quyền kiêm nhiệm % không hợp lệ.', t; end if;
      end loop;
      if c is null then ex := '{}'; end if;
      update erp_user set extra = ex where id = (e->>'id')::uuid and not is_admin;
    elsif c is null or r is null then
      update erp_user set extra = '{}' where id = (e->>'id')::uuid and not is_admin;
    end if;
    update erp_user set co = c, role = r where id = (e->>'id')::uuid and not is_admin;
    k := k + 1;
  end loop;
  return k;
end $$;

create or replace function erp_admin_delete_user(p_token text, p_user uuid) returns void language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user;
begin
  u := erp_require_admin(p_token);
  delete from erp_user where id = p_user and not is_admin;
end $$;

create or replace function erp_admin_set_cfg(p_token text, p_cfg jsonb) returns jsonb language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user; nv jsonb;
begin
  u := erp_require_admin(p_token);
  nv := jsonb_build_object('tol', greatest(0, least(50, coalesce((p_cfg->>'tol')::numeric, 5))),
                          'poAuto', greatest(0, coalesce((p_cfg->>'poAuto')::numeric, 0)),
                          'credit', coalesce((p_cfg->>'credit')::boolean, true),
                          'selfApprove', coalesce((p_cfg->>'selfApprove')::boolean, false));
  update erp_cfg set v = nv where k = 'main';
  return nv;
end $$;

create or replace function erp_admin_reset_co(p_token text, p_co text) returns int language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user; n int;
begin
  u := erp_require_admin(p_token);
  if not (p_co = any(erp_cos())) then raise exception 'Mã công ty không hợp lệ.'; end if;
  delete from erp_doc where co = p_co;
  get diagnostics n = row_count;
  update erp_cfg set v = jsonb_set(v, array[p_co], to_jsonb(coalesce((v->>p_co)::int, 0) + 1), true) where k = 'epoch';
  return n;
end $$;

-- ---------- Quyền gọi hàm ----------
do $$
declare f text;
begin
  foreach f in array array[
    'erp_iso()','erp_cos()','erp_genpw()','erp_auth(text)','erp_require_admin(text)','erp_balance(text,text)',
    'erp_user_json(erp_user)','erp_create_admin(text,text,text)','erp_type_role(text)','erp_role_for(erp_user,text)','erp_can_approve(erp_user)'] loop
    execute 'revoke execute on function ' || f || ' from public';
    if exists (select 1 from pg_roles where rolname='anon') then execute 'revoke execute on function ' || f || ' from anon'; end if;
    if exists (select 1 from pg_roles where rolname='authenticated') then execute 'revoke execute on function ' || f || ' from authenticated'; end if;
  end loop;
  foreach f in array array[
    'erp_login(text,text)','erp_logout(text)','erp_change_password(text,text,text)','erp_sync(text,text,timestamptz)',
    'erp_doc_create(text,text,text,jsonb,text,text)','erp_doc_decide(text,text,text,boolean,text,text)',
    'erp_admin_import(text,jsonb)','erp_admin_reset_pw(text,uuid)','erp_admin_assign(text,jsonb)',
    'erp_admin_delete_user(text,uuid)','erp_admin_set_cfg(text,jsonb)','erp_admin_reset_co(text,text)'] loop
    if exists (select 1 from pg_roles where rolname='anon') then execute 'grant execute on function ' || f || ' to anon'; end if;
    if exists (select 1 from pg_roles where rolname='authenticated') then execute 'grant execute on function ' || f || ' to authenticated'; end if;
  end loop;
end $$;


-- >>>>>>>>>> sql/002_ledger.sql
-- =====================================================================
-- ERP Lab 2.0 – P1: lõi sổ cái trên máy chủ
-- Sổ nhật ký hợp nhất (erp_je, erp_je_line), hệ thống tài khoản theo Phụ lục II TT 99/2025/TT-BTC,
-- xác định tài khoản tự động, định giá kho bình quân di động, dữ liệu gốc tối thiểu.
-- Bất biến 1: trình duyệt không gửi được dòng Nợ/Có. Mọi bút toán đi qua erp_post().
-- Chạy lại nhiều lần vẫn an toàn.
-- =====================================================================

-- ---------- Bảng ----------
create table if not exists erp_acct(
  code text primary key,
  name text not null,
  kind text not null check (kind in ('A','L','E','R','X','C')),   -- tài sản, nợ, vốn, doanh thu/thu nhập, chi phí, kết chuyển
  recon text check (recon in ('AR','AP','INV','ADV','FA','PAY')),  -- tài khoản đối chiếu với sổ phụ
  manual boolean not null default true,                            -- cho phép bút toán tay (FB50, từ P3)
  cc_req boolean not null default false,                           -- bắt buộc trung tâm chi phí (từ P8)
  from_phase text not null default 'P1',
  active boolean not null default true
);
create table if not exists erp_acct_det(
  k text primary key,
  acc text not null references erp_acct(code),
  note text not null default ''
);
create table if not exists erp_mat(
  co text not null, code text not null, name text not null, unit text not null,
  mtype text not null default 'HH', acc text not null default '156',
  open_qty numeric not null default 0, open_cost numeric not null default 0,
  buy_price numeric not null default 0, sell_price numeric not null default 0,
  active boolean not null default true,
  primary key(co, code)
);
create table if not exists erp_partner(
  co text not null, code text not null, kind text not null check (kind in ('V','C')),
  name text not null, mst text not null default '', terms int not null default 30,
  credit_lim numeric not null default 0, price_factor numeric not null default 1,
  active boolean not null default true,
  primary key(co, code)
);
create table if not exists erp_val(
  co text not null, mat text not null, qty numeric not null default 0, value numeric not null default 0,
  primary key(co, mat)
);
create table if not exists erp_je(
  co text not null, id text not null,
  doc_id text, doc_type text not null, post_date date not null,
  fy int not null, period int not null,
  created_by uuid, created_at timestamptz not null default clock_timestamp(),
  memo text not null default '',
  primary key(co, id)
);
create table if not exists erp_je_line(
  co text not null, je_id text not null, ln int not null,
  acc text not null references erp_acct(code),
  dr numeric not null default 0, cr numeric not null default 0,
  partner text, mat text, qty numeric, memo text not null default '',
  primary key(co, je_id, ln),
  foreign key (co, je_id) references erp_je(co, id),
  check (dr >= 0 and cr >= 0 and (dr = 0) <> (cr = 0))
);
create index if not exists erp_je_doc on erp_je(co, doc_id);
create index if not exists erp_je_line_acc on erp_je_line(co, acc);
create index if not exists erp_je_line_partner on erp_je_line(co, acc, partner);

alter table erp_acct enable row level security;
alter table erp_acct_det enable row level security;
alter table erp_mat enable row level security;
alter table erp_partner enable row level security;
alter table erp_val enable row level security;
alter table erp_je enable row level security;
alter table erp_je_line enable row level security;
do $$ begin
  if exists (select 1 from pg_roles where rolname='anon') then
    execute 'revoke all on erp_acct, erp_acct_det, erp_mat, erp_partner, erp_val, erp_je, erp_je_line from anon';
  end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then
    execute 'revoke all on erp_acct, erp_acct_det, erp_mat, erp_partner, erp_val, erp_je, erp_je_line from authenticated';
  end if;
end $$;

-- ---------- Bất biến 5: chứng từ kế toán không sửa, không xóa ----------
create or replace function erp_je_immutable() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('erp.allow_purge', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  raise exception 'Chứng từ kế toán đã ghi sổ không được sửa hay xóa. Muốn điều chỉnh, lập bút toán đảo (FB08).';
end $$;
drop trigger if exists erp_je_lock on erp_je;
create trigger erp_je_lock before update or delete on erp_je for each row execute function erp_je_immutable();
drop trigger if exists erp_je_line_lock on erp_je_line;
create trigger erp_je_line_lock before update or delete on erp_je_line for each row execute function erp_je_immutable();

-- ---------- Hệ thống tài khoản (Phụ lục II TT 99/2025/TT-BTC; xem SPEC mục 7) ----------
insert into erp_acct(code,name,kind,recon,manual,cc_req,from_phase) values
 ('111','Tiền mặt','A',null,true,false,'P1'),
 ('112','Tiền gửi không kỳ hạn','A',null,true,false,'P1'),
 ('113','Tiền đang chuyển','A',null,false,false,'P3'),
 ('131','Phải thu của khách hàng','A','AR',false,false,'P1'),
 ('1331','Thuế GTGT được khấu trừ của hàng hóa, dịch vụ','A',null,true,false,'P1'),
 ('1332','Thuế GTGT được khấu trừ của TSCĐ','A',null,true,false,'P6'),
 ('1381','Tài sản thiếu chờ xử lý','A',null,true,false,'P3'),
 ('1388','Phải thu khác','A',null,true,false,'P3'),
 ('141','Tạm ứng','A','ADV',false,false,'P3'),
 ('151','Hàng mua đang đi đường','A','INV',false,false,'P4'),
 ('152','Nguyên liệu, vật liệu','A','INV',false,false,'P7'),
 ('153','Công cụ, dụng cụ','A','INV',false,false,'P6'),
 ('154','Chi phí sản xuất, kinh doanh dở dang','A',null,false,false,'P7'),
 ('155','Sản phẩm','A','INV',false,false,'P7'),
 ('156','Hàng hóa','A','INV',false,false,'P1'),
 ('157','Hàng gửi đi bán','A','INV',false,false,'P5'),
 ('211','Tài sản cố định hữu hình','A','FA',false,false,'P6'),
 ('213','Tài sản cố định vô hình','A','FA',false,false,'P6'),
 ('2141','Hao mòn TSCĐ hữu hình','A','FA',false,false,'P6'),
 ('2143','Hao mòn TSCĐ vô hình','A','FA',false,false,'P6'),
 ('2293','Dự phòng phải thu khó đòi','A',null,true,false,'P5'),
 ('2294','Dự phòng giảm giá hàng tồn kho','A',null,true,false,'P10'),
 ('2411','Mua sắm TSCĐ','A',null,false,false,'P6'),
 ('242','Chi phí chờ phân bổ','A',null,true,false,'P3'),
 ('331','Phải trả cho người bán','L','AP',false,false,'P1'),
 ('33311','Thuế GTGT đầu ra','L',null,true,false,'P1'),
 ('3334','Thuế thu nhập doanh nghiệp','L',null,true,false,'P10'),
 ('3335','Thuế thu nhập cá nhân','L',null,true,false,'P9'),
 ('3339','Phí, lệ phí và các khoản phải nộp khác','L',null,true,false,'P10'),
 ('334','Phải trả người lao động','L','PAY',false,false,'P9'),
 ('335','Chi phí phải trả','L',null,true,false,'P3'),
 ('3381','Tài sản thừa chờ giải quyết','L',null,true,false,'P3'),
 ('3382','Kinh phí công đoàn','L',null,true,false,'P9'),
 ('3383','Bảo hiểm xã hội','L',null,true,false,'P9'),
 ('3384','Bảo hiểm y tế','L',null,true,false,'P9'),
 ('3386','Bảo hiểm thất nghiệp','L',null,true,false,'P9'),
 ('3387','Doanh thu chờ phân bổ','L',null,true,false,'P5'),
 ('3388','Phải trả, phải nộp khác','L',null,true,false,'P3'),
 ('3411','Các khoản đi vay','L',null,true,false,'P3'),
 ('4111','Vốn góp của chủ sở hữu','E',null,true,false,'P1'),
 ('4211','Lợi nhuận sau thuế chưa phân phối lũy kế đến cuối năm trước','E',null,true,false,'P10'),
 ('4212','Lợi nhuận sau thuế chưa phân phối năm nay','E',null,true,false,'P10'),
 ('511','Doanh thu bán hàng và cung cấp dịch vụ','R',null,false,false,'P1'),
 ('515','Doanh thu hoạt động tài chính','R',null,true,false,'P3'),
 ('521','Các khoản giảm trừ doanh thu','R',null,false,false,'P5'),
 ('621','Chi phí nguyên liệu, vật liệu trực tiếp','X',null,false,false,'P7'),
 ('622','Chi phí nhân công trực tiếp','X',null,false,false,'P7'),
 ('6271','Chi phí nhân viên phân xưởng','X',null,true,true,'P7'),
 ('6272','Chi phí vật liệu','X',null,true,true,'P7'),
 ('6273','Chi phí dụng cụ sản xuất','X',null,true,true,'P7'),
 ('6274','Chi phí khấu hao TSCĐ','X',null,true,true,'P7'),
 ('6277','Chi phí dịch vụ mua ngoài','X',null,true,true,'P7'),
 ('6278','Chi phí bằng tiền khác','X',null,true,true,'P7'),
 ('632','Giá vốn hàng bán','X',null,false,false,'P1'),
 ('635','Chi phí tài chính','X',null,true,false,'P3'),
 ('6411','Chi phí nhân viên','X',null,true,true,'P3'),
 ('6412','Chi phí vật liệu, bao bì','X',null,true,true,'P3'),
 ('6413','Chi phí dụng cụ, đồ dùng','X',null,true,true,'P3'),
 ('6414','Chi phí khấu hao TSCĐ','X',null,true,true,'P3'),
 ('6415','Thuế, phí, lệ phí','X',null,true,true,'P3'),
 ('6417','Chi phí dịch vụ mua ngoài','X',null,true,true,'P3'),
 ('6418','Chi phí bằng tiền khác','X',null,true,true,'P3'),
 ('6421','Chi phí nhân viên quản lý','X',null,true,true,'P3'),
 ('6422','Chi phí vật liệu quản lý','X',null,true,true,'P3'),
 ('6423','Chi phí đồ dùng văn phòng','X',null,true,true,'P3'),
 ('6424','Chi phí khấu hao TSCĐ','X',null,true,true,'P3'),
 ('6425','Thuế, phí và lệ phí','X',null,true,true,'P3'),
 ('6426','Chi phí dự phòng','X',null,true,true,'P3'),
 ('6427','Chi phí dịch vụ mua ngoài','X',null,true,true,'P3'),
 ('6428','Chi phí bằng tiền khác','X',null,true,true,'P3'),
 ('711','Thu nhập khác','R',null,true,false,'P6'),
 ('811','Chi phí khác','X',null,true,false,'P6'),
 ('82111','Chi phí thuế TNDN hiện hành theo quy định của Luật thuế TNDN','X',null,true,false,'P10'),
 ('911','Xác định kết quả kinh doanh','C',null,false,false,'P10')
on conflict (code) do update set name=excluded.name, kind=excluded.kind, recon=excluded.recon,
  manual=excluded.manual, cc_req=excluded.cc_req, from_phase=excluded.from_phase;

-- ---------- Xác định tài khoản (SPEC mục 8) ----------
insert into erp_acct_det(k,acc,note) values
 ('CASH','111','Tiền mặt'),
 ('BANK','112','Tiền gửi không kỳ hạn'),
 ('INV_HH','156','Tồn kho hàng hóa'),
 ('AR','131','Phải thu khách hàng'),
 ('AP','331','Phải trả người bán'),
 ('VAT_IN','1331','Thuế GTGT đầu vào'),
 ('VAT_OUT','33311','Thuế GTGT đầu ra'),
 ('REV','511','Doanh thu bán hàng'),
 ('COGS','632','Giá vốn hàng bán'),
 ('EQUITY','4111','Vốn góp chủ sở hữu (mở sổ)')
on conflict (k) do update set acc=excluded.acc, note=excluded.note;

create or replace function erp_ad(p_k text) returns text language sql stable as
$$ select acc from erp_acct_det where k = p_k $$;

-- Tham số thuế: mặc định 8% theo NĐ 174/2025/NĐ-CP (đến 31/12/2026). Giảng viên đổi trong SPRO.
update erp_cfg set v = v || '{"vat":0.08}'::jsonb where k = 'main' and not (v ? 'vat');

-- ---------- Dữ liệu gốc tối thiểu (giống hằng số giao diện bản 1; P2 thay bằng màn hình MM01/XK01/XD01) ----------
insert into erp_mat(co,code,name,unit,mtype,acc,open_qty,open_cost,buy_price,sell_price)
select c, m.code, m.name, m.unit, 'HH', '156', m.oq, m.oc, m.bp, m.sp
  from unnest(erp_cos()) c,
  (values ('HH01','Laptop văn phòng 14 inch','Cái',20,18500000,18500000,23900000),
          ('HH02','Màn hình 24 inch IPS','Cái',40,2600000,2600000,3450000),
          ('HH03','Máy in laser A4','Cái',15,3900000,3900000,4990000),
          ('HH04','Chuột không dây','Cái',100,290000,290000,420000),
          ('HH05','Bàn phím cơ','Cái',50,950000,950000,1290000)) as m(code,name,unit,oq,oc,bp,sp)
on conflict (co,code) do nothing;
insert into erp_partner(co,code,kind,name,mst,terms,credit_lim,price_factor)
select c, p.code, p.kind, p.name, p.mst, p.terms, p.lim, p.f
  from unnest(erp_cos()) c,
  (values ('NCC01','V','Công ty TNHH Phân phối Tin học Sao Mai','4201234567',30,0,1.00),
          ('NCC02','V','Công ty CP Thiết bị Văn phòng Hải Âu','0312345678',15,0,0.97),
          ('NCC03','V','Công ty TNHH Linh kiện Bến Thành','0309876543',45,0,1.03),
          ('KH01','C','Công ty TNHH Du lịch Biển Xanh','4201112223',30,300000000,1),
          ('KH02','C','Công ty CP Thủy sản Hòn Tre','4203334445',30,500000000,1),
          ('KH03','C','Cửa hàng Tin học Phước Hải','4205556667',15,150000000,1)) as p(code,kind,name,mst,terms,lim,f)
on conflict (co,code) do nothing;

-- ---------- Tiện ích ----------
create or replace function erp_vat() returns numeric language sql stable as
$$ select coalesce((select (v->>'vat')::numeric from erp_cfg where k='main'), 0.10) $$;

create or replace function erp_num(j jsonb, k text) returns numeric language sql immutable as
$$ select case when j ? k and jsonb_typeof(j->k) in ('number','string') and (j->>k) ~ '^-?[0-9]+(\.[0-9]+)?$'
               then (j->>k)::numeric end $$;

create or replace function erp_date(p text) returns date language plpgsql immutable as $$
begin
  if p is null or p !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Ngày chứng từ không hợp lệ (cần dạng YYYY-MM-DD).'; end if;
  return p::date;
exception when datetime_field_overflow or invalid_datetime_format then
  raise exception 'Ngày chứng từ không hợp lệ.';
end $$;

-- Số dư tài khoản (Nợ – Có) đọc từ sổ cái
create or replace function erp_balance(p_co text, p_acc text) returns numeric language sql stable
set search_path = public, extensions as $$
  select coalesce(sum(dr - cr), 0) from erp_je_line where co = p_co and acc = p_acc
$$;
create or replace function erp_balance_p(p_co text, p_acc text, p_partner text) returns numeric language sql stable as $$
  select coalesce(sum(dr - cr), 0) from erp_je_line where co = p_co and acc = p_acc and partner = p_partner
$$;

-- ---------- Cửa duy nhất tạo bút toán ----------
-- p_lines: [{a, dr|cr, p (đối tượng), mat, q, memo}] do máy chủ lập. Trả về bản sao dạng giao diện dùng.
create or replace function erp_post(p_co text, p_doc_id text, p_doc_type text, p_date date, p_by uuid,
                                    p_lines jsonb, p_memo text default '') returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare l jsonb; a erp_acct; s int; v_id text; n int := 0; tdr numeric := 0; tcr numeric := 0;
        dr numeric; cr numeric; outl jsonb := '[]'; y int := extract(year from p_date);
begin
  if jsonb_typeof(p_lines) <> 'array' then raise exception 'Bút toán không hợp lệ.'; end if;
  perform pg_advisory_xact_lock(hashtext('erp:je:' || p_co));
  select coalesce(max(substr(id, 7)::int), 0) + 1 into s from erp_je where co = p_co and fy = y;
  v_id := 'JE' || y || lpad(s::text, 6, '0');
  insert into erp_je(co,id,doc_id,doc_type,post_date,fy,period,created_by,memo)
  values (p_co, v_id, p_doc_id, p_doc_type, p_date, y, extract(month from p_date), p_by, coalesce(p_memo,''));
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
    if a.recon in ('AR','AP') and not exists (select 1 from erp_partner where co = p_co and code = l->>'p'
          and kind = case a.recon when 'AR' then 'C' else 'V' end) then
      raise exception 'Dòng ghi TK % thiếu đối tượng công nợ hợp lệ.', a.code;
    end if;
    if a.recon = 'INV' and not exists (select 1 from erp_mat where co = p_co and code = l->>'mat') then
      raise exception 'Dòng ghi TK % thiếu mã vật tư hợp lệ.', a.code;
    end if;
    n := n + 1;
    insert into erp_je_line(co,je_id,ln,acc,dr,cr,partner,mat,qty,memo)
    values (p_co, v_id, n, a.code, dr, cr, nullif(l->>'p',''), nullif(l->>'mat',''), erp_num(l,'q'), coalesce(l->>'memo',''));
    tdr := tdr + dr; tcr := tcr + cr;
    outl := outl || jsonb_strip_nulls(jsonb_build_object('a',a.code,'dr',nullif(dr,0),'cr',nullif(cr,0),
              'p',nullif(l->>'p',''),'mat',nullif(l->>'mat',''),'q',erp_num(l,'q')));
  end loop;
  if n < 2 then raise exception 'Bút toán phải có ít nhất hai dòng.'; end if;
  if tdr <> tcr then raise exception 'Bút toán không cân: tổng Nợ % khác tổng Có %.', tdr, tcr; end if;
  return jsonb_build_object('je', v_id, 'lines', outl);
end $$;

-- ---------- Định giá kho bình quân di động ----------
create or replace function erp_val_in(p_co text, p_mat text, p_qty numeric, p_value numeric) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  insert into erp_val(co,mat,qty,value) values (p_co,p_mat,p_qty,p_value)
  on conflict (co,mat) do update set qty = erp_val.qty + excluded.qty, value = erp_val.value + excluded.value;
end $$;
create or replace function erp_val_out(p_co text, p_mat text, p_qty numeric) returns numeric
language plpgsql security definer set search_path = public, extensions as $$
declare v erp_val; cost numeric;
begin
  select * into v from erp_val where co = p_co and mat = p_mat for update;
  if not found or v.qty < p_qty then
    raise exception 'Không đủ tồn kho %: còn % trong kho. Báo Thủ kho lập đề nghị mua (ME51N).', p_mat, coalesce(v.qty,0);
  end if;
  cost := case when v.qty = p_qty then v.value else round(v.value / v.qty * p_qty) end;
  update erp_val set qty = qty - p_qty, value = value - cost where co = p_co and mat = p_mat;
  return cost;
end $$;

-- ---------- Chứng từ mở sổ ----------
create or replace function erp_open_co(p_co text) returns text language plpgsql
security definer set search_path = public, extensions as $$
declare lines jsonb := '[]'; tot numeric := 0; m erp_mat; r jsonb; ts text := erp_iso(); d date := make_date(extract(year from now())::int,1,1);
begin
  perform pg_advisory_xact_lock(hashtext('erp:open:' || p_co));
  if exists (select 1 from erp_doc where co = p_co and type = 'OB') then return 'exists'; end if;
  lines := lines || jsonb_build_object('a',erp_ad('CASH'),'dr',200000000) || jsonb_build_object('a',erp_ad('BANK'),'dr',3000000000);
  tot := 3200000000;
  for m in select * from erp_mat where co = p_co and open_qty > 0 order by code loop
    lines := lines || jsonb_build_object('a',m.acc,'dr',m.open_qty*m.open_cost,'mat',m.code,'q',m.open_qty);
    tot := tot + m.open_qty*m.open_cost;
    perform erp_val_in(p_co, m.code, m.open_qty, m.open_qty*m.open_cost);
  end loop;
  lines := lines || jsonb_build_object('a',erp_ad('EQUITY'),'cr',tot);
  r := erp_post(p_co, 'OB00001', 'OB', d, null, lines, 'Số dư đầu kỳ');
  insert into erp_doc(co,id,type,seq,status,data) values (p_co,'OB00001','OB',1,'posted',
    jsonb_build_object('type','OB','seq',1,'no','0000000001','status','posted','at',ts,'date',to_char(d,'YYYY-MM-DD'),
      'memo','Số dư đầu kỳ','je',r->'lines','jeNo',r->>'je','hist','[]'::jsonb));
  return r->>'je';
end $$;

-- ---------- Tính toán nghiệp vụ trên máy chủ ----------
create or replace function erp_doc_data(p_co text, p_id text) returns jsonb language sql stable as
$$ select data || jsonb_build_object('status', status) from erp_doc where co = p_co and id = p_id $$;

-- Tổng số lượng theo dòng (line) của các chứng từ con còn hiệu lực
create or replace function erp_kid_qty(p_co text, p_type text, p_fld text, p_parent text, p_line int) returns numeric
language sql stable as $$
  select coalesce(sum((it->>'qty')::numeric), 0)
    from erp_doc d, jsonb_array_elements(d.data->'items') it
   where d.co = p_co and d.type = p_type and d.status <> 'rejected' and d.data->>p_fld = p_parent
     and (it->>'line')::int = p_line
$$;
create or replace function erp_kid_amt(p_co text, p_type text, p_fld text, p_parent text) returns numeric
language sql stable as $$
  select coalesce(sum((data->>'amount')::numeric), 0) from erp_doc
   where co = p_co and type = p_type and status in ('pending','posted') and data->>p_fld = p_parent
$$;
-- Dư nợ tín dụng = số dư 131 của khách + giá trị (có thuế) phần đơn bán đã xác nhận chưa lập hóa đơn
create or replace function erp_exposure(p_co text, p_cust text) returns numeric language sql stable as $$
  select erp_balance_p(p_co, erp_ad('AR'), p_cust)
       + coalesce((select sum(((it.v->>'qty')::numeric - erp_kid_qty(p_co,'BI','so',d.id,(it.i-1)::int)) * (it.v->>'price')::numeric)
                     from erp_doc d, jsonb_array_elements(d.data->'items') with ordinality it(v,i)
                    where d.co = p_co and d.type = 'SO' and d.status = 'approved' and d.data->>'cust' = p_cust), 0) * (1 + erp_vat())
$$;

-- ---------- Lập chứng từ (thay bản 1) ----------
-- erp_doc_create: định nghĩa trong 004_masterdata.sql
-- erp_doc_decide: định nghĩa trong 004_masterdata.sql
-- erp_sync: định nghĩa trong 004_masterdata.sql
create or replace function erp_admin_set_cfg(p_token text, p_cfg jsonb) returns jsonb language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user; nv jsonb;
begin
  u := erp_require_admin(p_token);
  nv := jsonb_build_object('tol', greatest(0, least(50, coalesce((p_cfg->>'tol')::numeric, 5))),
                          'poAuto', greatest(0, coalesce((p_cfg->>'poAuto')::numeric, 0)),
                          'credit', coalesce((p_cfg->>'credit')::boolean, true),
                          'selfApprove', coalesce((p_cfg->>'selfApprove')::boolean, false),
                          'vat', case when (p_cfg->>'vat') in ('0','0.05','0.08','0.1','0.10') then (p_cfg->>'vat')::numeric else erp_vat() end);
  update erp_cfg set v = v || nv where k = 'main';
  return nv;
end $$;

-- ---------- Làm mới một công ty: xóa chứng từ và sổ, mở sổ lại ----------
create or replace function erp_admin_reset_co(p_token text, p_co text) returns int language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user; n int;
begin
  u := erp_require_admin(p_token);
  if not (p_co = any(erp_cos())) then raise exception 'Mã công ty không hợp lệ.'; end if;
  select count(*) into n from erp_doc where co = p_co and type <> 'OB';
  perform erp_purge_co(p_co);
  update erp_cfg set v = jsonb_set(v, array[p_co], to_jsonb(coalesce((v->>p_co)::int, 0) + 1), true) where k = 'epoch';
  return n;
end $$;
create or replace function erp_purge_co(p_co text) returns void language plpgsql
security definer set search_path = public, extensions as $$
begin
  perform set_config('erp.allow_purge', 'on', true);
  delete from erp_je_line where co = p_co;
  delete from erp_je where co = p_co;
  perform set_config('erp.allow_purge', '', true);
  delete from erp_doc where co = p_co;
  delete from erp_val where co = p_co;
  perform erp_open_co(p_co);
end $$;

-- ---------- Chuyển dữ liệu bản 1 (SPEC mục 14) ----------
create or replace function erp_map_acc(a text) returns text language sql immutable as $$
  select case a when '1111' then '111' when '1121' then '112' when '1561' then '156' when '5111' then '511' when '411' then '4111' else a end
$$;
create or replace function erp_migrate_v1() returns jsonb language plpgsql
security definer set search_path = public, extensions as $$
declare c text; d erp_doc; nj jsonb; posted jsonb; k int := 0; o int := 0; l jsonb;
begin
  foreach c in array erp_cos() loop
    if not exists (select 1 from erp_doc where co = c and type = 'OB') then perform erp_open_co(c); o := o + 1; end if;
    for d in select * from erp_doc where co = c and type <> 'OB' and status <> 'rejected'
               and jsonb_typeof(data->'je') = 'array' and not (data ? 'jeNo') order by data->>'at', id loop
      select coalesce(jsonb_agg(j || jsonb_build_object('a', erp_map_acc(j->>'a'))), '[]') into nj from jsonb_array_elements(d.data->'je') j;
      posted := erp_post(c, d.id, d.type, coalesce(nullif(d.data->>'date','')::date, current_date), nullif(d.data->>'by','')::uuid, nj, 'Chuyển từ bản 1');
      for l in select * from jsonb_array_elements(posted->'lines') loop
        if l->>'a' = '156' and l ? 'mat' then
          perform erp_val_in(c, l->>'mat', coalesce((l->>'q')::numeric,0) * case when l ? 'dr' then 1 else -1 end,
                             coalesce((l->>'dr')::numeric,0) - coalesce((l->>'cr')::numeric,0));
        end if;
      end loop;
      update erp_doc set data = data || jsonb_build_object('je', posted->'lines', 'jeNo', posted->>'je')
                                     || case when data ? 'acc' then jsonb_build_object('acc', erp_map_acc(data->>'acc')) else '{}'::jsonb end,
                         updated_at = clock_timestamp()
       where co = c and id = d.id;
      k := k + 1;
    end loop;
    update erp_doc set data = data || jsonb_build_object('acc', erp_map_acc(data->>'acc')), updated_at = clock_timestamp()
     where co = c and data ? 'acc' and data->>'acc' <> erp_map_acc(data->>'acc');
  end loop;
  return jsonb_build_object('opened', o, 'migrated', k);
end $$;

-- ---------- Quyền gọi hàm ----------
do $$
declare f text;
begin
  foreach f in array array[
    'erp_ad(text)','erp_vat()','erp_num(jsonb,text)','erp_date(text)','erp_balance_p(text,text,text)',
    'erp_post(text,text,text,date,uuid,jsonb,text)','erp_val_in(text,text,numeric,numeric)','erp_val_out(text,text,numeric)',
    'erp_open_co(text)','erp_doc_data(text,text)','erp_kid_qty(text,text,text,text,int)','erp_kid_amt(text,text,text,text)',
    'erp_exposure(text,text)','erp_purge_co(text)','erp_map_acc(text)','erp_migrate_v1()','erp_je_immutable()'] loop
    execute 'revoke execute on function ' || f || ' from public';
    if exists (select 1 from pg_roles where rolname='anon') then execute 'revoke execute on function ' || f || ' from anon'; end if;
    if exists (select 1 from pg_roles where rolname='authenticated') then execute 'revoke execute on function ' || f || ' from authenticated'; end if;
  end loop;
end $$;

-- ---------- Mở sổ các công ty mới, chuyển dữ liệu bản 1 nếu có ----------
select erp_migrate_v1();

-- >>>>>>>>>> sql/003_hardening.sql
-- =====================================================================
-- ERP Lab 2.0 – P1: cố định search_path cho các hàm phụ (cảnh báo function_search_path_mutable của Supabase).
-- Chạy lại an toàn.
-- =====================================================================
do $$
declare f text;
begin
  foreach f in array array[
    'erp_iso()','erp_cos()','erp_user_json(erp_user)','erp_type_role(text)','erp_role_for(erp_user,text)',
    'erp_can_approve(erp_user)','erp_ad(text)','erp_vat()','erp_num(jsonb,text)','erp_date(text)',
    'erp_balance_p(text,text,text)','erp_doc_data(text,text)','erp_kid_qty(text,text,text,text,int)',
    'erp_kid_amt(text,text,text,text)','erp_exposure(text,text)','erp_map_acc(text)','erp_je_immutable()'] loop
    execute 'alter function ' || f || ' set search_path = public, extensions';
  end loop;
end $$;

-- >>>>>>>>>> sql/004_masterdata.sql
-- =====================================================================
-- ERP Lab 2.0 – P2: cấu trúc tổ chức, vai trò – quyền – gói vai trò, dữ liệu gốc, duyệt trường nhạy cảm.
-- Quyền kiểm tra trên máy chủ theo bảng erp_role_perm (SPEC mục 4). Chạy lại nhiều lần vẫn an toàn.
-- erp_admin_assign được định nghĩa tại đây (thay bản trước). erp_doc_create, erp_doc_decide, erp_md_json, erp_sync: xem 005_gl_cash.sql.
-- =====================================================================

-- ---------- Cấu trúc tổ chức (SPEC mục 3) ----------
create table if not exists erp_org(
  co text not null, kind text not null check (kind in ('PLANT','SLOC','PORG','SORG','DCHAN','CC','PC')),
  code text not null, name text not null, parent text, note text not null default '',
  primary key(co, kind, code)
);
insert into erp_org(co,kind,code,name,parent,note)
select c, o.kind, o.code, o.name, o.parent, o.note from unnest(erp_cos()) c,
 (values ('PLANT','1000','Nhà máy – kho Nha Trang',null,''),
         ('SLOC','1001','Kho nguyên vật liệu, linh kiện','1000','Vật tư loại NVL'),
         ('SLOC','1002','Kho thành phẩm','1000','Vật tư loại TP'),
         ('SLOC','1003','Kho hàng hóa','1000','Vật tư loại HH'),
         ('PORG','1000','Tổ chức mua hàng',null,'Phòng Mua hàng'),
         ('SORG','1000','Tổ chức bán hàng',null,'Phòng Kinh doanh'),
         ('DCHAN','10','Kênh bán buôn – doanh nghiệp','1000',''),
         ('DCHAN','20','Kênh bán lẻ','1000',''),
         ('CC','CC100','Ban Giám đốc',null,'Chi phí quản lý doanh nghiệp'),
         ('CC','CC200','Phòng Mua hàng',null,'Chi phí quản lý doanh nghiệp'),
         ('CC','CC300','Kho vận',null,'Chi phí bán hàng'),
         ('CC','CC400','Phòng Kinh doanh',null,'Chi phí bán hàng'),
         ('CC','CC500','Xưởng lắp ráp',null,'Chi phí sản xuất chung'),
         ('CC','CC510','Tổ kiểm thử',null,'Chi phí sản xuất chung'),
         ('CC','CC600','Phòng Nhân sự',null,'Chi phí quản lý doanh nghiệp'),
         ('CC','CC700','Phòng Kế toán',null,'Chi phí quản lý doanh nghiệp'),
         ('PC','PC10','Thiết bị tin học (thương mại)',null,'Vật tư HH'),
         ('PC','PC20','Máy tính lắp ráp',null,'Vật tư TP'),
         ('PC','PC30','Dịch vụ lắp đặt, bảo trì',null,'Vật tư DV')) as o(kind,code,name,parent,note)
on conflict do nothing;

-- ---------- Vai trò, quyền, gói vai trò (SPEC mục 4) ----------
create table if not exists erp_role(
  code text primary key, name text not null, dept text not null, descr text not null default '',
  phase text not null default 'P2', sort int not null default 99
);
insert into erp_role(code,name,dept,descr,phase,sort) values
 ('GD','Giám đốc','Ban Giám đốc','Xem báo cáo; duyệt cấp 2 (từ P4), duyệt khóa sổ (P10)','P2',1),
 ('MH','Nhân viên mua hàng','Mua hàng','Đơn mua, dữ liệu gốc nhà cung cấp và vật tư, bảng giá mua','P1',2),
 ('KHO','Thủ kho','Kho vận','Đề nghị mua, nhập kho, xuất kho','P1',3),
 ('KD','Nhân viên kinh doanh','Kinh doanh','Đơn bán, dữ liệu gốc khách hàng','P1',4),
 ('SX','Kế hoạch – Quản đốc','Sản xuất','BOM, MRP, lệnh sản xuất (P7)','P7',5),
 ('NS','Nhân sự – tiền lương','Nhân sự','Hồ sơ, chấm công, tính lương (P9)','P9',6),
 ('KT','Kế toán công nợ (phải trả + phải thu)','Kế toán','Gộp AP và AR; vai trò của bản 1','P1',7),
 ('AP','Kế toán phải trả','Kế toán','Hóa đơn mua, đề nghị chi','P2',8),
 ('AR','Kế toán phải thu','Kế toán','Hóa đơn bán, thu tiền','P2',9),
 ('GT','Kế toán kho – giá thành','Kế toán','Giá thành, chênh lệch (P7–P8)','P7',10),
 ('TS','Kế toán tài sản cố định','Kế toán','TSCĐ, khấu hao (P6)','P6',11),
 ('TH','Kế toán tổng hợp','Kế toán','Bút toán tổng hợp, kết chuyển (P3)','P3',12),
 ('TQ','Thủ quỹ','Kế toán','Thu chi tiền mặt (P3)','P3',13),
 ('KTT','Kế toán trưởng','Kế toán','Duyệt chứng từ tài chính, gỡ khóa, duyệt thay đổi dữ liệu gốc nhạy cảm','P1',14),
 ('KSNB','Kiểm toán nội bộ','Kiểm soát nội bộ','Chỉ đọc: sổ sách, nhật ký thay đổi, công cụ kiểm toán (P11)','P2',15)
on conflict (code) do update set name=excluded.name, dept=excluded.dept, descr=excluded.descr, phase=excluded.phase, sort=excluded.sort;

create table if not exists erp_role_perm(
  role text not null references erp_role(code), tc text not null, act text not null check (act in ('C','A','V')),
  primary key(role, tc, act)
);
-- C = lập/thay đổi, A = phê duyệt, V = xem. Giao dịch danh sách/báo cáo chung (ME5A, ME2N, VA05, MB51…) mở cho mọi vai trò ở giao diện.
insert into erp_role_perm(role,tc,act)
select r, tc, a from (values
 ('KHO','ME51N','C'),('KHO','MIGO','C'),('KHO','VL01N','C'),
 ('MH','ME21N','C'),('MH','MM01','C'),('MH','XK01','C'),('MH','ME11','C'),('MH','FBL1N','V'),
 ('KD','VA01','C'),('KD','XD01','C'),('KD','FBL5N','V'),
 ('AP','MIRO','C'),('AP','F-53','C'),('AP','FBL1N','V'),('AP','ZNKC','V'),('AP','F.01','V'),
 ('AR','VF01','C'),('AR','F-28','C'),('AR','FBL5N','V'),('AR','ZNKC','V'),('AR','F.01','V'),
 ('KTT','SBWP','A'),('KTT','ME54N','A'),('KTT','ME29N','A'),('KTT','MRBR','A'),('KTT','VKM3','A'),('KTT','ZFAP','A'),('KTT','ZMDA','A'),
 ('KTT','FBL1N','V'),('KTT','FBL5N','V'),('KTT','ZNKC','V'),('KTT','F.01','V'),('KTT','ZCHG','V'),
 ('GD','FBL1N','V'),('GD','FBL5N','V'),('GD','ZNKC','V'),('GD','F.01','V'),('GD','ZCHG','V'),
 ('KSNB','FBL1N','V'),('KSNB','FBL5N','V'),('KSNB','ZNKC','V'),('KSNB','F.01','V'),('KSNB','ZCHG','V'),
 ('TH','ZNKC','V'),('TH','F.01','V'),('TQ','ZNKC','V'),('GT','ZNKC','V'),('GT','F.01','V'),('TS','ZNKC','V'),('TS','F.01','V')
) as p(r,tc,a) on conflict do nothing;

create table if not exists erp_role_pack(
  code text primary key, name text not null, seats jsonb not null, note text not null default '', sort int not null default 9
);
-- seats: mỗi ghế là một mảng vai trò (vai trò chính + kiêm nhiệm), ghép theo nguyên tắc ít xung đột nhất (SPEC 4.3).
insert into erp_role_pack(code,name,seats,note,sort) values
 ('PK1','Mua – Bán (5 ghế, như bản 1)','[["KHO"],["MH"],["KD"],["KT"],["KTT"]]','Bài 1–2: chu trình mua hàng và bán hàng',1),
 ('PK2','Mua – Bán tách công nợ','[["KHO"],["MH","KD"],["AP"],["AR"],["KTT"]]','Thấy rõ tách phải trả và phải thu',2),
 ('PK3','Tiền và sổ cái','[["TQ"],["TH"],["AP"],["AR"],["KTT"]]','Từ P3',3),
 ('PK4','Kiểm soát và kiểm toán','[["KHO","KD"],["MH"],["KT"],["KTT"],["KSNB"]]','Có một người kiểm toán nội bộ độc lập',4),
 ('PK5','Sản xuất và giá thành','[["SX"],["KHO"],["MH","KD"],["GT","KT"],["KTT"]]','Từ P7',5)
on conflict (code) do update set name=excluded.name, seats=excluded.seats, note=excluded.note, sort=excluded.sort;

alter table erp_org enable row level security;
alter table erp_role enable row level security;
alter table erp_role_perm enable row level security;
alter table erp_role_pack enable row level security;

-- ---------- Dữ liệu gốc mở rộng ----------
alter table erp_mat alter column acc drop not null;
alter table erp_mat add column if not exists min_stock numeric not null default 0;
alter table erp_mat add column if not exists sloc text;
alter table erp_mat add column if not exists pc text;
alter table erp_mat add column if not exists valid_from date not null default date '2026-01-01';
alter table erp_mat add column if not exists updated_at timestamptz not null default clock_timestamp();
alter table erp_mat drop constraint if exists erp_mat_mtype_chk;
alter table erp_mat add constraint erp_mat_mtype_chk check (mtype in ('HH','NVL','TP','DV'));
update erp_mat set sloc = coalesce(sloc,'1003'), pc = coalesce(pc,'PC10'), min_stock = case when min_stock = 0 then
   case code when 'HH01' then 10 when 'HH02' then 15 when 'HH03' then 5 when 'HH04' then 30 when 'HH05' then 15 else 0 end else min_stock end
 where mtype = 'HH';

alter table erp_partner add column if not exists address text not null default '';
alter table erp_partner add column if not exists bank_acc text not null default '';
alter table erp_partner add column if not exists bank_name text not null default '';
alter table erp_partner add column if not exists confirmed boolean not null default true;
alter table erp_partner add column if not exists updated_at timestamptz not null default clock_timestamp();

insert into erp_acct_det(k,acc,note) values ('INV_NVL','152','Tồn kho nguyên vật liệu, linh kiện'),('INV_TP','155','Tồn kho sản phẩm (thành phẩm)')
on conflict (k) do update set acc=excluded.acc, note=excluded.note;

-- Dữ liệu gốc bổ sung (giống nhau cho 8 công ty; sinh viên tạo thêm qua MM01/XK01/XD01)
insert into erp_mat(co,code,name,unit,mtype,acc,open_qty,open_cost,buy_price,sell_price,min_stock,sloc,pc)
select c, m.code, m.name, m.unit, m.t, case m.t when 'NVL' then '152' when 'TP' then '155' when 'HH' then '156' end,
       0, 0, m.bp, m.sp, m.mn, case m.t when 'NVL' then '1001' when 'TP' then '1002' when 'HH' then '1003' end,
       case m.t when 'TP' then 'PC20' when 'DV' then 'PC30' else 'PC10' end
  from unnest(erp_cos()) c,
  (values ('NV01','Vỏ máy tính ATX','Cái','NVL',650000,0,10),
          ('NV02','Bo mạch chủ B760','Cái','NVL',2900000,0,10),
          ('NV03','CPU Core i5 thế hệ 14','Cái','NVL',5400000,0,10),
          ('NV04','RAM DDR5 16GB','Thanh','NVL',1250000,0,20),
          ('NV05','SSD NVMe 512GB','Cái','NVL',1150000,0,10),
          ('NV06','Nguồn máy tính 550W','Cái','NVL',850000,0,10),
          ('TP01','Máy tính bộ văn phòng VP-i5','Bộ','TP',0,15900000,0),
          ('TP02','Máy tính bộ đồ họa DH-i5 32GB','Bộ','TP',0,19900000,0),
          ('DV01','Dịch vụ lắp đặt tại chỗ','Lần','DV',0,500000,0),
          ('DV02','Gói bảo trì 12 tháng','Gói','DV',0,1800000,0)) as m(code,name,unit,t,bp,sp,mn)
on conflict (co,code) do nothing;
update erp_partner set bank_acc = case code when 'NCC01' then '1903 5566 7788 01' when 'NCC02' then '0071 0012 3456 02' when 'NCC03' then '1170 2233 4455 03' else bank_acc end,
                       bank_name = 'Ngân hàng TMCP Mô phỏng – CN Nha Trang',
                       address = case code when 'NCC01' then 'Số 12 đường Thái Nguyên, Nha Trang' when 'NCC02' then 'Số 48 đường Ba Tháng Hai, TP. Hồ Chí Minh'
                         when 'NCC03' then 'Số 7 đường Lê Lai, TP. Hồ Chí Minh' when 'KH01' then 'Số 20 đường Trần Phú, Nha Trang'
                         when 'KH02' then 'Khu công nghiệp Suối Dầu, Cam Lâm' when 'KH03' then 'Số 155 đường 23 Tháng 10, Nha Trang' else address end
 where bank_acc = '' and address = '';
insert into erp_partner(co,code,kind,name,mst,terms,credit_lim,price_factor,address,bank_acc,bank_name)
select c, p.code, p.kind, p.name, p.mst, p.terms, p.lim, 1, p.addr, p.bank, case when p.bank<>'' then 'Ngân hàng TMCP Mô phỏng – CN Nha Trang' else '' end
  from unnest(erp_cos()) c,
  (values ('NCC04','V','Công ty TNHH Linh kiện Máy tính Phú Quang','0315550404',30,0,'Số 90 đường Nguyễn Trãi, TP. Hồ Chí Minh','2001 4455 6677 04'),
          ('NCC05','V','Công ty CP Vận tải Biển Đông Xanh','4201550505',15,0,'Cảng Ba Ngòi, Cam Ranh','2001 4455 6677 05'),
          ('NCC06','V','Công ty TNHH Bao bì Khánh Hòa Mới','4201550606',30,0,'Khu công nghiệp Đắc Lộc, Nha Trang','2001 4455 6677 06'),
          ('KH04','C','Trường Trung học Hải Đăng (mô phỏng)','4201660404',30,400000000,'Số 5 đường Hùng Vương, Nha Trang',''),
          ('KH05','C','Công ty CP Khách sạn Vịnh Ngọc','4201660505',30,350000000,'Số 88 đường Trần Phú, Nha Trang',''),
          ('KH06','C','Phòng khám Đa khoa Tâm An (mô phỏng)','4201660606',15,120000000,'Số 30 đường Lý Thánh Tông, Nha Trang','')) as p(code,kind,name,mst,terms,lim,addr,bank)
on conflict (co,code) do nothing;

-- Bảng giá mua theo nhà cung cấp (ME11). Đơn mua đề xuất giá theo bảng này; không có thì lấy giá tham khảo × hệ số NCC.
create table if not exists erp_price(
  co text not null, vendor text not null, mat text not null, price numeric not null check (price > 0),
  valid_from date not null default date '2026-01-01', by uuid, at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key(co, vendor, mat, valid_from)
);
insert into erp_price(co,vendor,mat,price)
select c, p.v, p.m, p.pr from unnest(erp_cos()) c,
 (values ('NCC04','NV01',640000),('NCC04','NV02',2850000),('NCC04','NV03',5350000),('NCC04','NV04',1230000),('NCC04','NV05',1120000),('NCC04','NV06',830000),
         ('NCC03','NV02',2950000),('NCC03','NV03',5500000),('NCC03','NV04',1290000),('NCC03','NV05',1180000)) as p(v,m,pr)
on conflict do nothing;

-- Thay đổi dữ liệu gốc: nhật ký (applied) và yêu cầu chờ duyệt cho trường nhạy cảm (pending → approved/rejected)
create table if not exists erp_md_change(
  id bigserial primary key, co text not null, obj text not null check (obj in ('MAT','VEN','CUS','PRICE')),
  key text not null, field text not null, old_val text, new_val text,
  status text not null check (status in ('applied','pending','approved','rejected')),
  by uuid, at timestamptz not null default clock_timestamp(), dec_by uuid, dec_at timestamptz, note text not null default ''
);
create index if not exists erp_md_change_co on erp_md_change(co, at);
alter table erp_price enable row level security;
alter table erp_md_change enable row level security;
do $$ begin
  if exists (select 1 from pg_roles where rolname='anon') then
    execute 'revoke all on erp_org, erp_role, erp_role_perm, erp_role_pack, erp_price, erp_md_change from anon';
    execute 'revoke all on sequence erp_md_change_id_seq from anon';
  end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then
    execute 'revoke all on erp_org, erp_role, erp_role_perm, erp_role_pack, erp_price, erp_md_change from authenticated';
    execute 'revoke all on sequence erp_md_change_id_seq from authenticated';
  end if;
end $$;

-- ---------- Hàm quyền ----------
create or replace function erp_type_role(p_type text) returns text language sql immutable set search_path = public, extensions as $$
  select case p_type when 'PR' then 'KHO' when 'GR' then 'KHO' when 'DL' then 'KHO' when 'PO' then 'MH' when 'SO' then 'KD'
                     when 'IV' then 'AP' when 'PAY' then 'AP' when 'BI' then 'AR' when 'RC' then 'AR' end
$$;
create or replace function erp_type_tc(p_type text) returns text language sql immutable set search_path = public, extensions as $$
  select case p_type when 'PR' then 'ME51N' when 'PO' then 'ME21N' when 'GR' then 'MIGO' when 'IV' then 'MIRO' when 'PAY' then 'F-53'
                     when 'SO' then 'VA01' when 'DL' then 'VL01N' when 'BI' then 'VF01' when 'RC' then 'F-28' end
$$;
-- Vai trò hiệu lực: vai trò chính + vai trò kiêm nhiệm; KT (bản 1) = AP + AR
create or replace function erp_expand(p_roles text[]) returns text[] language sql immutable set search_path = public, extensions as $$
  select coalesce(array_agg(distinct x), '{}') from (
    select unnest(p_roles) x union all select unnest(array['AP','AR']) where 'KT' = any(p_roles)) t where x is not null
$$;
create or replace function erp_roles_of(u erp_user) returns text[] language sql stable set search_path = public, extensions as $$
  select case when u.role is null then '{}'::text[] else erp_expand(array[u.role] || array(select x from unnest(coalesce(u.extra,'{}')) x where x not like 'T:%')) end
$$;
create or replace function erp_can(p_roles text[], p_tc text, p_act text) returns boolean language sql stable set search_path = public, extensions as $$
  select 'GV' = any(p_roles) or exists (select 1 from erp_role_perm where role = any(p_roles) and tc = p_tc and act = p_act)
$$;
create or replace function erp_role_for(u erp_user, p_type text) returns text language sql stable set search_path = public, extensions as $$
  select coalesce(
    (select r from unnest(erp_roles_of(u)) r where exists (select 1 from erp_role_perm where role = r and tc = erp_type_tc(p_type) and act = 'C') order by r limit 1),
    case when ('T:' || p_type) = any(coalesce(u.extra,'{}')) then erp_type_role(p_type) end)
$$;
create or replace function erp_can_approve(u erp_user) returns boolean language sql stable set search_path = public, extensions as $$
  select erp_can(erp_roles_of(u), 'SBWP', 'A') or 'T:AP' = any(coalesce(u.extra,'{}'))
$$;
-- Vai trò thao tác: sinh viên = vai trò hiệu lực; giảng viên = vai trò đang chọn "Thao tác như"
create or replace function erp_act_roles(u erp_user, p_act_role text) returns text[] language plpgsql stable set search_path = public, extensions as $$
begin
  if u.is_admin then
    if coalesce(p_act_role,'') in ('','GV') then return array['GV']; end if;
    if not exists (select 1 from erp_role where code = p_act_role) then raise exception 'Vai trò % không hợp lệ.', p_act_role; end if;
    return erp_expand(array[p_act_role]);
  end if;
  return erp_roles_of(u);
end $$;
create or replace function erp_fm(n numeric) returns text language sql immutable set search_path = public, extensions as
$$ select replace(to_char(round(n), 'FM999G999G999G999G990'), ',', '.') $$;

-- ---------- Lập chứng từ (thay bản P1: quyền theo erp_role_perm; kiểm tra dữ liệu gốc còn hiệu lực) ----------
-- erp_doc_create: định nghĩa tại 005_gl_cash.sql

-- ---------- Phê duyệt chứng từ ----------
-- erp_doc_decide: định nghĩa tại 005_gl_cash.sql

-- ---------- Dữ liệu gốc: lập / thay đổi (MM01-02, XK01-02, XD01-02) ----------
-- Trường nhạy cảm: thay đổi nằm ở trạng thái chờ đến khi một người khác có quyền ZMDA duyệt.
create or replace function erp_md_sensitive(p_obj text, p_field text) returns boolean language sql immutable set search_path = public, extensions as $$
  select (p_obj in ('VEN','CUS') and p_field in ('name','mst','bank_acc','bank_name','credit_lim','terms','active'))
      or (p_obj = 'MAT' and p_field = 'active')
$$;

create or replace function erp_md_save(p_token text, p_co text, p_obj text, p_key text, p_data jsonb, p_act_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u erp_user; roles text[]; tc text; cur jsonb; f text; nv text; ov text; applied text[] := '{}'; pend text[] := '{}';
        k text := upper(trim(coalesce(p_key,''))); v_kind text; s int; created boolean := false; m erp_mat; pa erp_partner;
        allowed_fields text[];
begin
  u := erp_auth(p_token);
  if not u.is_admin and p_co is distinct from u.co then raise exception 'Không được sửa dữ liệu gốc của công ty khác.'; end if;
  if not (p_co = any(erp_cos())) then raise exception 'Mã công ty không hợp lệ.'; end if;
  if p_obj not in ('MAT','VEN','CUS') then raise exception 'Đối tượng dữ liệu gốc không hợp lệ.'; end if;
  tc := case p_obj when 'MAT' then 'MM01' when 'VEN' then 'XK01' else 'XD01' end;
  roles := erp_act_roles(u, p_act_role);
  if not erp_can(roles, tc, 'C') then raise exception 'Vai trò của bạn không được lập/thay đổi dữ liệu gốc này (SU53, cần quyền %).', tc; end if;
  if jsonb_typeof(p_data) <> 'object' then raise exception 'Dữ liệu không hợp lệ.'; end if;
  perform pg_advisory_xact_lock(hashtext('erp:md:' || p_co));

  if p_obj = 'MAT' then
    allowed_fields := array['name','unit','buy_price','sell_price','min_stock','valid_from','active'];
    if k = '' then
      if coalesce(p_data->>'mtype','') not in ('HH','NVL','TP','DV') then raise exception 'Loại vật tư phải là HH, NVL, TP hoặc DV.'; end if;
      v_kind := case p_data->>'mtype' when 'HH' then 'HH' when 'NVL' then 'NV' when 'TP' then 'TP' else 'DV' end;
      select coalesce(max(substring(code from '\d+$')::int),0)+1 into s from erp_mat where co = p_co and code ~ ('^' || v_kind || '\d+$');
      k := v_kind || lpad(s::text, 2, '0');
      if coalesce(trim(p_data->>'name'),'') = '' or coalesce(trim(p_data->>'unit'),'') = '' then raise exception 'Thiếu tên hoặc đơn vị tính.'; end if;
      if exists (select 1 from erp_mat where co = p_co and lower(name) = lower(trim(p_data->>'name'))) then
        raise exception 'Đã có vật tư cùng tên "%". Kiểm tra trùng trước khi tạo mới.', trim(p_data->>'name'); end if;
      insert into erp_mat(co,code,name,unit,mtype,acc,buy_price,sell_price,min_stock,sloc,pc,valid_from)
      values (p_co, k, trim(p_data->>'name'), trim(p_data->>'unit'), p_data->>'mtype',
              case p_data->>'mtype' when 'HH' then erp_ad('INV_HH') when 'NVL' then erp_ad('INV_NVL') when 'TP' then erp_ad('INV_TP') end,
              greatest(0,coalesce(erp_num(p_data,'buy_price'),0)), greatest(0,coalesce(erp_num(p_data,'sell_price'),0)),
              greatest(0,coalesce(erp_num(p_data,'min_stock'),0)),
              case p_data->>'mtype' when 'NVL' then '1001' when 'TP' then '1002' when 'HH' then '1003' end,
              case p_data->>'mtype' when 'TP' then 'PC20' when 'DV' then 'PC30' else 'PC10' end,
              coalesce(nullif(p_data->>'valid_from','')::date, current_date));
      insert into erp_md_change(co,obj,key,field,old_val,new_val,status,by) values (p_co,'MAT',k,'*tạo mới',null,trim(p_data->>'name'),'applied',u.id);
      return jsonb_build_object('key',k,'created',true,'applied','{}'::text[],'pending','{}'::text[]);
    end if;
    select to_jsonb(x) into cur from erp_mat x where co = p_co and code = k;
    if cur is null then raise exception 'Không tìm thấy vật tư %.', k; end if;
  else
    allowed_fields := array['name','mst','address','terms','bank_acc','bank_name','active'] || case when p_obj = 'CUS' then array['credit_lim'] else '{}'::text[] end;
    v_kind := case p_obj when 'VEN' then 'V' else 'C' end;
    if p_data ? 'mst' then
      if coalesce(p_data->>'mst','') !~ '^\d{10}(-\d{3})?$' then raise exception 'Mã số thuế phải có 10 chữ số (hoặc 10 số và 3 số chi nhánh dạng 0123456789-001).'; end if;
      if exists (select 1 from erp_partner where co = p_co and erp_partner.kind = v_kind and mst = p_data->>'mst' and code <> k) then
        raise exception 'Mã số thuế % đã thuộc % khác (%). Không tạo trùng đối tượng.', p_data->>'mst',
          case v_kind when 'V' then 'nhà cung cấp' else 'khách hàng' end,
          (select code from erp_partner where co = p_co and erp_partner.kind = v_kind and mst = p_data->>'mst' and code <> k limit 1); end if;
    end if;
    if k = '' then
      if coalesce(trim(p_data->>'name'),'') = '' or coalesce(p_data->>'mst','') = '' then raise exception 'Thiếu tên hoặc mã số thuế.'; end if;
      select coalesce(max(substring(code from '\d+$')::int),0)+1 into s from erp_partner where co = p_co and erp_partner.kind = v_kind;
      k := case v_kind when 'V' then 'NCC' else 'KH' end || lpad(s::text, 2, '0');
      -- Đối tượng mới: dùng được sau khi người có quyền ZMDA xác nhận (kiểm soát nhà cung cấp/khách hàng "ma")
      insert into erp_partner(co,code,kind,name,mst,terms,credit_lim,address,bank_acc,bank_name,confirmed)
      values (p_co, k, v_kind, trim(p_data->>'name'), p_data->>'mst', greatest(0,least(120,coalesce(erp_num(p_data,'terms'),30)::int)),
              case when v_kind = 'C' then greatest(0,coalesce(erp_num(p_data,'credit_lim'),0)) else 0 end,
              coalesce(trim(p_data->>'address'),''), coalesce(trim(p_data->>'bank_acc'),''), coalesce(trim(p_data->>'bank_name'),''), false);
      insert into erp_md_change(co,obj,key,field,old_val,new_val,status,by) values (p_co,p_obj,k,'*tạo mới',null,
        trim(p_data->>'name') || ' · MST ' || (p_data->>'mst') || ' · TK NH ' || coalesce(nullif(trim(p_data->>'bank_acc'),''),'(chưa có)')
        || coalesce(' ' || nullif(trim(p_data->>'bank_name'),''),'') || ' · hạn TT ' || greatest(0,least(120,coalesce(erp_num(p_data,'terms'),30)::int)) || ' ngày'
        || case when v_kind = 'C' then ' · hạn mức ' || erp_fm(greatest(0,coalesce(erp_num(p_data,'credit_lim'),0))) else '' end,'pending',u.id);
      return jsonb_build_object('key',k,'created',true,'applied','{}'::text[],'pending',array['*tạo mới']);
    end if;
    select to_jsonb(x) into cur from erp_partner x where co = p_co and code = k and x.kind = v_kind;
    if cur is null then raise exception 'Không tìm thấy đối tượng %.', k; end if;
  end if;

  -- Thay đổi từng trường
  foreach f in array allowed_fields loop
    if not (p_data ? f) then continue; end if;
    nv := nullif(trim(p_data->>f), ''); ov := cur->>f;
    if f in ('buy_price','sell_price','min_stock','credit_lim','terms') then
      if nv is null or nv !~ '^\d+(\.\d+)?$' then raise exception 'Giá trị % không hợp lệ.', f; end if;
      if f = 'terms' and nv::numeric > 120 then raise exception 'Thời hạn thanh toán tối đa 120 ngày.'; end if;
      if ov is not null and nv::numeric = ov::numeric then continue; end if;
    elsif f = 'active' then
      nv := case when nv in ('true','1','t') then 'true' else 'false' end;
      if nv = ov then continue; end if;
    elsif f = 'valid_from' then
      if nv is null then continue; end if;
      if nv::date::text = ov then continue; end if;
    else
      if coalesce(nv,'') = coalesce(ov,'') then continue; end if;
      if f in ('name','unit','mst') and nv is null then raise exception 'Trường % không được để trống.', f; end if;
    end if;
    if erp_md_sensitive(p_obj, f) then
      if exists (select 1 from erp_md_change where co = p_co and obj = p_obj and key = k and field = f and status = 'pending') then
        raise exception 'Trường % của % đang có một thay đổi chờ duyệt.', f, k; end if;
      insert into erp_md_change(co,obj,key,field,old_val,new_val,status,by) values (p_co,p_obj,k,f,ov,nv,'pending',u.id);
      pend := pend || f;
    else
      perform erp_md_apply(p_co, p_obj, k, f, nv);
      insert into erp_md_change(co,obj,key,field,old_val,new_val,status,by) values (p_co,p_obj,k,f,ov,nv,'applied',u.id);
      applied := applied || f;
    end if;
  end loop;
  return jsonb_build_object('key',k,'created',false,'applied',applied,'pending',pend);
end $$;

create or replace function erp_md_apply(p_co text, p_obj text, p_key text, p_field text, p_val text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_obj = 'MAT' then
    execute format('update erp_mat set %I = $1::%s, updated_at = clock_timestamp() where co = $2 and code = $3', p_field,
      case when p_field in ('buy_price','sell_price','min_stock') then 'numeric' when p_field = 'active' then 'boolean' when p_field = 'valid_from' then 'date' else 'text' end)
      using p_val, p_co, p_key;
  else
    execute format('update erp_partner set %I = $1::%s, updated_at = clock_timestamp() where co = $2 and code = $3', p_field,
      case when p_field in ('credit_lim') then 'numeric' when p_field = 'terms' then 'int' when p_field = 'active' then 'boolean' else 'text' end)
      using p_val, p_co, p_key;
  end if;
end $$;

-- Duyệt thay đổi nhạy cảm và xác nhận đối tượng mới (ZMDA)
create or replace function erp_md_decide(p_token text, p_co text, p_id bigint, p_ok boolean, p_note text, p_act_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u erp_user; c erp_md_change;
begin
  u := erp_auth(p_token);
  if not u.is_admin and p_co is distinct from u.co then raise exception 'Không được duyệt dữ liệu gốc của công ty khác.'; end if;
  if not erp_can(erp_act_roles(u, p_act_role), 'ZMDA', 'A') then raise exception 'Chỉ Kế toán trưởng được duyệt thay đổi dữ liệu gốc nhạy cảm (ZMDA).'; end if;
  select * into c from erp_md_change where id = p_id and co = p_co for update;
  if not found or c.status <> 'pending' then raise exception 'Yêu cầu không tồn tại hoặc đã được xử lý.'; end if;
  if c."by" = u.id and not u.is_admin then raise exception 'Vi phạm bất kiêm nhiệm: không được tự duyệt thay đổi dữ liệu gốc do chính mình yêu cầu.'; end if;
  if not p_ok and coalesce(trim(p_note),'') = '' then raise exception 'Hãy ghi lý do từ chối.'; end if;
  if p_ok then
    if c.field = '*tạo mới' then update erp_partner set confirmed = true, updated_at = clock_timestamp() where co = p_co and code = c.key;
    else perform erp_md_apply(p_co, c.obj, c.key, c.field, c.new_val); end if;
  elsif c.field = '*tạo mới' then
    update erp_partner set active = false, updated_at = clock_timestamp() where co = p_co and code = c.key;
  end if;
  update erp_md_change set status = case when p_ok then 'approved' else 'rejected' end, dec_by = u.id, dec_at = clock_timestamp(),
         note = coalesce(p_note,'') where id = p_id;
  return jsonb_build_object('status', case when p_ok then 'approved' else 'rejected' end);
end $$;

-- Bảng giá mua (ME11)
create or replace function erp_price_save(p_token text, p_co text, p_vendor text, p_mat text, p_price numeric, p_from date, p_act_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u erp_user; ov numeric;
begin
  u := erp_auth(p_token);
  if not u.is_admin and p_co is distinct from u.co then raise exception 'Không được sửa bảng giá của công ty khác.'; end if;
  if not erp_can(erp_act_roles(u, p_act_role), 'ME11', 'C') then raise exception 'Vai trò của bạn không được cập nhật bảng giá mua (SU53).'; end if;
  if not exists (select 1 from erp_partner where co = p_co and code = p_vendor and kind = 'V') then raise exception 'Nhà cung cấp không hợp lệ.'; end if;
  if not exists (select 1 from erp_mat where co = p_co and code = p_mat and mtype in ('HH','NVL')) then raise exception 'Vật tư không mua ngoài được.'; end if;
  if coalesce(p_price,0) <= 0 then raise exception 'Đơn giá phải lớn hơn 0.'; end if;
  select price into ov from erp_price where co = p_co and vendor = p_vendor and mat = p_mat and valid_from = coalesce(p_from, current_date);
  insert into erp_price(co,vendor,mat,price,valid_from,by) values (p_co,p_vendor,p_mat,round(p_price),coalesce(p_from,current_date),u.id)
  on conflict (co,vendor,mat,valid_from) do update set price = excluded.price, by = excluded.by, updated_at = clock_timestamp();
  insert into erp_md_change(co,obj,key,field,old_val,new_val,status,by)
  values (p_co,'PRICE',p_vendor || '/' || p_mat,'price từ ' || to_char(coalesce(p_from,current_date),'DD/MM/YYYY'),ov::text,round(p_price)::text,'applied',u.id);
  return jsonb_build_object('ok', true);
end $$;

-- ---------- Giảng viên: phân công và gói vai trò ----------
create or replace function erp_admin_assign(p_token text, p_rows jsonb) returns int language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user; e jsonb; c text; r text; k int := 0; ex text[]; t text;
begin
  u := erp_require_admin(p_token);
  for e in select * from jsonb_array_elements(p_rows) loop
    c := nullif(e->>'co',''); r := nullif(e->>'role','');
    if c is not null and not (c = any(erp_cos())) then raise exception 'Mã công ty % không hợp lệ.', c; end if;
    if r is not null and not exists (select 1 from erp_role where code = r) then raise exception 'Vai trò % không hợp lệ.', r; end if;
    if e ? 'extra' and jsonb_typeof(e->'extra') = 'array' then
      select coalesce(array_agg(distinct x), '{}') into ex from jsonb_array_elements_text(e->'extra') x where x is distinct from r;
      foreach t in array ex loop
        if not (exists (select 1 from erp_role where code = t)
                or t in ('T:PR','T:PO','T:GR','T:IV','T:PAY','T:SO','T:DL','T:BI','T:RC','T:AP')) then
          raise exception 'Quyền kiêm nhiệm % không hợp lệ.', t; end if;
      end loop;
      if c is null then ex := '{}'; end if;
      update erp_user set extra = ex where id = (e->>'id')::uuid and not is_admin;
    elsif c is null or r is null then
      update erp_user set extra = '{}' where id = (e->>'id')::uuid and not is_admin;
    end if;
    update erp_user set co = c, role = r where id = (e->>'id')::uuid and not is_admin;
    k := k + 1;
  end loop;
  return k;
end $$;

-- Ma trận xung đột vai trò (SPEC 4.3): điểm 0–3, từ 2 trở lên là xung đột cần cảnh báo
create table if not exists erp_role_conflict(a text not null, b text not null, score int not null, risk text not null default '', primary key(a,b));
alter table erp_role_conflict enable row level security;
do $$ begin
  if exists (select 1 from pg_roles where rolname='anon') then execute 'revoke all on erp_role_conflict from anon'; end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then execute 'revoke all on erp_role_conflict from authenticated'; end if;
end $$;
insert into erp_role_conflict(a,b,score,risk) values
 ('KHO','KT',3,'Vừa giữ hàng vừa ghi sổ'),('KHO','AP',3,'Vừa giữ hàng vừa ghi sổ'),('KHO','AR',3,'Vừa giữ hàng vừa ghi sổ'),
 ('KHO','MH',2,'Tự đặt mua và tự nhận hàng'),('KHO','KD',1,'Vừa bán vừa xuất kho'),
 ('MH','KT',2,'Tự đặt mua và tự đề nghị trả tiền'),('MH','AP',2,'Tự đặt mua và tự đề nghị trả tiền'),
 ('KD','KT',2,'Tự bán và tự xóa nợ'),('KD','AR',2,'Tự bán và tự xóa nợ'),
 ('TQ','TH',3,'Giữ tiền và ghi sổ'),('TQ','AP',3,'Giữ tiền và ghi sổ'),('TQ','AR',3,'Giữ tiền và ghi sổ'),('TQ','KT',3,'Giữ tiền và ghi sổ'),
 ('MH','KD',0,'')
on conflict (a,b) do update set score=excluded.score, risk=excluded.risk;
create or replace function erp_conflict(p_a text, p_b text) returns int language sql stable set search_path = public, extensions as $$
  select case when p_a = p_b then 0
              when 'KTT' in (p_a,p_b) and 'GD' not in (p_a,p_b) and 'KSNB' not in (p_a,p_b) then 3
              when 'KSNB' in (p_a,p_b) and 'GD' not in (p_a,p_b) then 3
              else coalesce((select score from erp_role_conflict where (a,b) in ((p_a,p_b),(p_b,p_a)) limit 1), 0) end
$$;

-- Áp gói vai trò cho một công ty (hoặc cả 8 nếu p_co rỗng). Thành viên xếp theo MSSV.
-- Thiếu người: ghế có KTT luôn là ghế chính; các ghế còn lại không đủ người được ghép vào người có điểm xung đột thấp nhất
-- (điểm = tổng xung đột với vai trò đang giữ + 1,5 × số vai trò), không bao giờ ghép vào người giữ KTT.
-- Thừa người: người thứ 6 trở đi nhận vai trò Giám đốc (chỉ xem, duyệt cấp 2 từ P4).
create or replace function erp_admin_apply_pack(p_token text, p_pack text, p_co text) returns jsonb language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user; pk erp_role_pack; c text; mem uuid[]; n int; nseat int; i int; seat jsonb; roles text[]; tgt int; out jsonb := '{}';
        ex jsonb; prim jsonb; rest jsonb; ktt jsonb; best numeric; sc numeric; j int;
begin
  u := erp_require_admin(p_token);
  select * into pk from erp_role_pack where code = p_pack;
  if not found then raise exception 'Gói vai trò không tồn tại.'; end if;
  nseat := jsonb_array_length(pk.seats);
  foreach c in array erp_cos() loop
    if coalesce(p_co,'') <> '' and c <> p_co then continue; end if;
    select array_agg(id order by username) into mem from erp_user where co = c and not is_admin;
    n := coalesce(array_length(mem,1),0);
    if n = 0 then continue; end if;
    if n >= nseat then
      prim := pk.seats; rest := '[]';
      for i in nseat+1..n loop prim := prim || jsonb_build_array(jsonb_build_array('GD')); end loop;
    else
      select coalesce(jsonb_agg(x.v order by x.o),'[]') into ktt from jsonb_array_elements(pk.seats) with ordinality x(v,o) where x.v ? 'KTT';
      select coalesce(jsonb_agg(x.v order by x.o),'[]') into rest from jsonb_array_elements(pk.seats) with ordinality x(v,o) where not (x.v ? 'KTT');
      prim := '[]';
      for i in 0 .. least(n - jsonb_array_length(ktt), jsonb_array_length(rest)) - 1 loop prim := prim || jsonb_build_array(rest->i); end loop;
      prim := prim || ktt;
      select coalesce(jsonb_agg(x.v order by x.o),'[]') into rest from jsonb_array_elements(rest) with ordinality x(v,o)
       where x.o > n - jsonb_array_length(ktt);
    end if;
    ex := prim;
    for i in 0 .. jsonb_array_length(rest) - 1 loop
      seat := rest->i; tgt := null; best := null;
      for j in 0 .. jsonb_array_length(ex) - 1 loop
        if (ex->j) ? 'KTT' and n > 1 then continue; end if;
        select coalesce(sum(erp_conflict(a.x, b.y)),0) + 1.5 * jsonb_array_length(ex->j) into sc
          from jsonb_array_elements_text(ex->j) a(x), jsonb_array_elements_text(seat) b(y);
        if best is null or sc < best then best := sc; tgt := j; end if;
      end loop;
      ex := jsonb_set(ex, array[tgt::text], (ex->tgt) || seat);
    end loop;
    for i in 1..n loop
      roles := array(select jsonb_array_elements_text(ex->(i-1)));
      update erp_user set role = roles[1], extra = coalesce(roles[2:], '{}') where id = mem[i];
    end loop;
    out := out || jsonb_build_object(c, ex);
  end loop;
  return out;
end $$;

-- ---------- Đồng bộ: thêm dữ liệu gốc, tổ chức, vai trò, quyền ----------
-- erp_md_json: định nghĩa tại 005_gl_cash.sql
-- erp_md_changed: định nghĩa tại 005_gl_cash.sql

-- erp_sync: định nghĩa tại 005_gl_cash.sql

-- ---------- Quyền gọi hàm ----------
do $$
declare f text;
begin
  foreach f in array array[
    'erp_type_tc(text)','erp_expand(text[])','erp_roles_of(erp_user)','erp_can(text[],text,text)','erp_act_roles(erp_user,text)',
    'erp_fm(numeric)','erp_conflict(text,text)','erp_md_sensitive(text,text)','erp_md_apply(text,text,text,text,text)'] loop
    execute 'revoke execute on function ' || f || ' from public';
    if exists (select 1 from pg_roles where rolname='anon') then execute 'revoke execute on function ' || f || ' from anon'; end if;
    if exists (select 1 from pg_roles where rolname='authenticated') then execute 'revoke execute on function ' || f || ' from authenticated'; end if;
  end loop;
  foreach f in array array[
    'erp_md_save(text,text,text,text,jsonb,text)','erp_md_decide(text,text,bigint,boolean,text,text)',
    'erp_price_save(text,text,text,text,numeric,date,text)','erp_admin_apply_pack(text,text,text)'] loop
    execute 'revoke execute on function ' || f || ' from public';
    if exists (select 1 from pg_roles where rolname='anon') then execute 'grant execute on function ' || f || ' to anon'; end if;
    if exists (select 1 from pg_roles where rolname='authenticated') then execute 'grant execute on function ' || f || ' to authenticated'; end if;
  end loop;
end $$;

-- >>>>>>>>>> sql/005_gl_cash.sql
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
  if d.data->>'decBy' = u.id::text and not u.is_admin then raise exception 'Vi phạm bất kiêm nhiệm: người đã duyệt chứng từ không tự thu, chi tiền.'; end if;
  if d.type in ('ADV','ADS') and d.data->>'emp' = u.username and not u.is_admin then
    raise exception 'Vi phạm bất kiêm nhiệm: Thủ quỹ không tự chi tạm ứng hoặc tự quyết toán tạm ứng cho chính mình.'; end if;
  amt := (d.data->>'amount')::numeric; nd := d.data;
  if d.type = 'PAY' then
    select * into pa from erp_partner where co = p_co and code = d.data->>'vendor';
    if not found or not pa.active then raise exception 'Nhà cung cấp % đang bị khóa (XK02) hoặc không tồn tại: không chi tiền.', d.data->>'vendor'; end if;
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
    -- Rút tiền gửi về quỹ: giấy báo Nợ của ngân hàng có ngay → ghi thẳng Có 112; kiểm tra lại số dư khả dụng lúc chi (RV2-03)
    if erp_balance(p_co, erp_ad('BANK')) + least(erp_balance(p_co, erp_ad('BANK_CLR')),0) < amt then
      raise exception 'Không đủ số dư tiền gửi để rút (đã trừ các khoản chi đang chuyển).'; end if;
    lines := jsonb_build_array(jsonb_build_object('a',erp_ad('CASH'),'dr',amt), jsonb_build_object('a',erp_ad('BANK'),'cr',amt));
    nd := nd || jsonb_build_object('bankDirect', true);
  elsif coalesce((select (v->>'bankClear')::boolean from erp_cfg where k = 'main'), true) then
    -- Nộp tiền mặt vào ngân hàng, chưa có giấy báo Có → TK 113 đến khi có sao kê
    lines := jsonb_build_array(jsonb_build_object('a',erp_ad('BANK_CLR'),'dr',amt), jsonb_build_object('a',erp_ad('CASH'),'cr',amt));
    nd := nd || jsonb_build_object('clr', erp_ad('BANK_CLR'));
  else
    -- Tắt TK 113 (SPRO): ghi thẳng Nợ 112 như ủy nhiệm chi (RV2-08)
    lines := jsonb_build_array(jsonb_build_object('a',erp_ad('BANK'),'dr',amt), jsonb_build_object('a',erp_ad('CASH'),'cr',amt));
    nd := nd || jsonb_build_object('bankDirect', true);
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
create or replace function erp_cash_return(p_token text, p_co text, p_id text, p_note text, p_act_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
-- Trả lại chứng từ đã duyệt nhưng Thủ quỹ chưa thu, chi (RV2-05): ví dụ người nhận không đến, sai số tiền. Không ghi sổ, có lý do và nhật ký.
declare u erp_user; r text; d erp_doc; ts text := erp_iso();
begin
  u := erp_auth(p_token);
  if not u.is_admin and p_co is distinct from u.co then raise exception 'Không được xử lý chứng từ của công ty khác.'; end if;
  if not (erp_can(erp_act_roles(u, p_act_role), 'ZTQ', 'C') or (not u.is_admin and erp_can_approve(u)) or u.is_admin) then
    raise exception 'Chỉ Thủ quỹ hoặc Kế toán trưởng được trả lại chứng từ chờ thu, chi.'; end if;
  if coalesce(trim(p_note),'') = '' then raise exception 'Hãy ghi lý do trả lại.'; end if;
  r := case when u.is_admin then coalesce(nullif(p_act_role,''),'GV') when erp_can(erp_act_roles(u, p_act_role), 'ZTQ', 'C') then 'TQ' else 'KTT' end;
  perform pg_advisory_xact_lock(hashtext('erp:doc:' || p_co));
  select * into d from erp_doc where co = p_co and id = p_id for update;
  if not found then raise exception 'Không tìm thấy chứng từ.'; end if;
  if d.status <> 'approved' or d.type not in ('PAY','RC','CJ','ADV','ADS') or (d.type in ('PAY','RC') and d.data->>'acc' <> erp_ad('CASH')) then
    raise exception 'Chứng từ không ở trạng thái chờ thủ quỹ thu, chi.'; end if;
  update erp_doc set status = 'rejected', updated_at = clock_timestamp(),
    data = data || jsonb_build_object('status','rejected','hist', coalesce(data->'hist','[]'::jsonb) ||
      jsonb_build_array(jsonb_build_object('at',ts,'by',u.id::text,'role',r,'act','return','note',trim(p_note))))
   where co = p_co and id = p_id;
  return jsonb_build_object('status','rejected');
end $$;

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
  if exists (select 1 from erp_doc where co = p_co and type = 'JE' and status = 'pending' and data->>'revOf' = p_bs) then
    raise exception 'Khoản tiền về này đang có đề nghị đảo (FB08) chờ duyệt. Xử lý đề nghị đảo trước khi phân bổ.'; end if;
  bi := erp_doc_data(p_co, p_bi);
  if bi is null or bi->>'type' <> 'BI' or bi->>'status' <> 'posted' then raise exception 'Hóa đơn bán không hợp lệ.'; end if;
  rem_s := abs((s->>'amount')::numeric) - coalesce((select sum((data->>'alloc')::numeric) from erp_doc where co = p_co and type = 'BS' and data->>'ref' = p_bs and status = 'posted' and not (data ? 'revBy')),0);
  rem_b := (bi->>'total')::numeric - erp_kid_amt(p_co,'RC','bi',p_bi) - erp_bs_alloc(p_co, p_bi);
  -- Không vượt số dư Có TK 3388 trên sổ cái (RV2-06: 3388 còn được ghi tay ở nghiệp vụ khác)
  rem_s := least(rem_s, greatest(-erp_balance(p_co, erp_ad('SUSPENSE')), 0));
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
      if src->>'type' = 'BS' and exists (select 1 from erp_doc where co = p_co and type = 'BS' and data->>'kind' = 'clr' and data->>'ref' = b->>'revOf' and status = 'posted' and not (data ? 'revBy')) then
        raise exception 'Khoản tiền về này đã được phân bổ cho hóa đơn. Đảo các chứng từ phân bổ trước.'; end if;
      if src->>'status' <> 'posted' then raise exception 'Chỉ đảo được bút toán đã ghi sổ.'; end if;
      if src ? 'revBy' or exists (select 1 from erp_doc where co = p_co and type = 'JE' and status <> 'rejected' and data->>'revOf' = b->>'revOf') then
        raise exception 'Bút toán này đã được đảo hoặc đang có đề nghị đảo.'; end if;
      if coalesce(trim(b->>'reason'),'') = '' then raise exception 'Thiếu lý do đảo.'; end if;
      for it in select * from jsonb_array_elements(src->'je') loop
        items := items || jsonb_strip_nulls(jsonb_build_object('a',it->>'a','dr',it->'cr','cr',it->'dr','cc',it->>'cc','memo',it->>'memo','p',it->>'p','mat',it->>'mat','q',it->'q'));
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
    if exists (select 1 from erp_doc where co = p_co and (
         (type in ('CJ','CNT') and status in ('pending','approved'))
      or (type in ('PAY','RC') and status in ('pending','approved') and data->>'acc' = erp_ad('CASH'))
      or (type in ('ADV','ADS') and status = 'approved'))) then
      raise exception 'Còn chứng từ thu, chi tiền mặt chờ duyệt hoặc chờ thủ quỹ. Xử lý xong mới kiểm quỹ.'; end if;
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
      if not found or not pa.active then raise exception 'Nhà cung cấp % đang bị khóa (XK02) hoặc không tồn tại: không duyệt chi.', d.data->>'vendor'; end if;
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
    if d.data->>'kind' = 'rev' then
      -- Kiểm tra lại lúc duyệt (RV2-01): chứng từ gốc chưa bị đảo, khoản treo chưa được phân bổ trong lúc chờ duyệt
      if erp_doc_data(p_co, d.data->>'revOf') ? 'revBy' then raise exception 'Chứng từ gốc đã được đảo.'; end if;
      if exists (select 1 from erp_doc where co = p_co and type = 'BS' and data->>'kind' = 'clr' and data->>'ref' = d.data->>'revOf' and status = 'posted' and not (data ? 'revBy')) then
        raise exception 'Khoản tiền về này đã được phân bổ cho hóa đơn trong lúc chờ duyệt. Từ chối đề nghị đảo này; đảo các chứng từ phân bổ trước rồi lập lại.'; end if;
    end if;
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
    -- Sổ quỹ đã thay đổi từ lúc lập biên bản (có phiếu thu, chi xác nhận trong lúc chờ duyệt): chênh lệch không còn đúng
    if erp_balance(p_co, erp_ad('CASH')) <> (d.data->>'book')::numeric then
      raise exception 'Số dư sổ quỹ đã thay đổi từ lúc lập biên bản (lúc lập % đồng, hiện % đồng). Từ chối biên bản này và kiểm quỹ lại.',
        erp_fm((d.data->>'book')::numeric), erp_fm(erp_balance(p_co, erp_ad('CASH'))); end if;
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
    'erp_cash_confirm(text,text,text,text)','erp_susp_clear(text,text,text,text,numeric,text)','erp_cash_return(text,text,text,text,text)'] loop
    execute 'revoke execute on function ' || f || ' from public';
    if exists (select 1 from pg_roles where rolname='anon') then execute 'grant execute on function ' || f || ' to anon'; end if;
    if exists (select 1 from pg_roles where rolname='authenticated') then execute 'grant execute on function ' || f || ' to authenticated'; end if;
  end loop;
end $$;
alter function erp_wdate(text) set search_path = public, extensions;

-- ---------- Tài khoản giảng viên: SỬA MẬT KHẨU TRƯỚC KHI CHẠY ----------
select erp_create_admin('gv', 'DoiMatKhauNay@2026', 'Giảng viên');
