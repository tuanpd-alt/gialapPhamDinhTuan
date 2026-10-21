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
create table if not exists erp_cfg(k text primary key, v jsonb not null);
insert into erp_cfg values ('main','{"tol":5,"poAuto":0,"credit":true}') on conflict do nothing;
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

create or replace function erp_balance(p_co text, p_acc text) returns numeric language sql stable
set search_path = public, extensions as $$
  select (case p_acc when '1111' then 200000000 when '1121' then 3000000000 else 0 end)::numeric
       + coalesce((select sum(coalesce((j->>'dr')::numeric,0) - coalesce((j->>'cr')::numeric,0))
           from erp_doc d, jsonb_array_elements(case when jsonb_typeof(d.data->'je')='array' then d.data->'je' else '[]'::jsonb end) j
          where d.co = p_co and d.status <> 'rejected' and j->>'a' = p_acc), 0)
$$;

create or replace function erp_user_json(u erp_user) returns jsonb language sql stable as $$
  select jsonb_build_object('id',u.id,'username',u.username,'full_name',u.full_name,'is_admin',u.is_admin,
    'co',u.co,'role',u.role,'grp',u.grp,'must_change',u.must_change)
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
       'co',x.co,'role',x.role,'grp',x.grp,'must_change',x.must_change,'last_login',x.last_login) order by x.username), '[]'::jsonb)
      into v_users from erp_user x;
  else
    select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'full_name',x.full_name,'is_admin',x.is_admin,'co',x.co,'role',x.role)), '[]'::jsonb)
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
  if r <> 'GV' and not (r = any(allowed)) then
    raise exception 'Vai trò % không được lập loại chứng từ này (SU53). Bất kiêm nhiệm.', r;
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
    if u.role is distinct from 'KTT' then raise exception 'Chỉ Kế toán trưởng được phê duyệt chứng từ.'; end if;
    if p_co is distinct from u.co then raise exception 'Không được phê duyệt chứng từ của công ty khác.'; end if;
    r := 'KTT';
  end if;
  select * into d from erp_doc where co = p_co and id = p_id for update;
  if not found then raise exception 'Không tìm thấy chứng từ.'; end if;
  if not ((d.type in ('PR','PO','PAY','RC') and d.status = 'pending') or (d.type in ('IV','SO') and d.status = 'blocked')) then
    raise exception 'Chứng từ không còn ở trạng thái chờ xử lý.';
  end if;
  if d.data->>'by' = u.id::text and not u.is_admin then
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
                 'act', case when p_ok then 'approve' else 'reject' end, 'note', coalesce(p_note,''))));
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
declare u erp_user; e jsonb; c text; r text; k int := 0;
begin
  u := erp_require_admin(p_token);
  for e in select * from jsonb_array_elements(p_rows) loop
    c := nullif(e->>'co',''); r := nullif(e->>'role','');
    if c is not null and not (c = any(erp_cos())) then raise exception 'Mã công ty % không hợp lệ.', c; end if;
    if r is not null and r not in ('KHO','MH','KD','KT','KTT') then raise exception 'Vai trò % không hợp lệ.', r; end if;
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
                          'credit', coalesce((p_cfg->>'credit')::boolean, true));
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
    'erp_user_json(erp_user)','erp_create_admin(text,text,text)'] loop
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

-- ---------- Tài khoản giảng viên: SỬA MẬT KHẨU TRƯỚC KHI CHẠY ----------
select erp_create_admin('gv', 'DoiMatKhauNay@2026', 'Giảng viên');
