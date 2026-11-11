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
create or replace function erp_doc_create(p_token text, p_co text, p_type text, p_body jsonb, p_note text, p_act_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  u erp_user; r text; st text; s int; v_id text; v_no text; ts text := erp_iso();
  pre text; po_auto numeric; b jsonb := p_body; src jsonb; it jsonb; items jsonb := '[]'; je jsonb := '[]';
  q numeric; pr numeric; i int; n int; net numeric := 0; vat numeric; total numeric; rate numeric := erp_vat();
  tol numeric; cfg jsonb; m erp_mat; pa erp_partner; d date; diff numeric; diffsum numeric := 0; bad text := '';
  cost numeric; costsum numeric := 0; amt numeric; rem numeric; posted jsonb; note text := coalesce(p_note,'');
begin
  u := erp_auth(p_token);
  if u.is_admin then
    r := coalesce(nullif(p_act_role,''), 'GV');
    if r not in ('GV','KHO','MH','KD','KT','KTT') then raise exception 'Vai trò không hợp lệ.'; end if;
  else
    if u.co is null or u.role is null then raise exception 'Bạn chưa được giảng viên phân công vào công ty.'; end if;
    if p_co is distinct from u.co then raise exception 'Không được ghi chứng từ cho công ty khác.'; end if;
  end if;
  if not (p_co = any(erp_cos())) then raise exception 'Mã công ty không hợp lệ.'; end if;
  if jsonb_typeof(b) <> 'object' then raise exception 'Dữ liệu chứng từ không hợp lệ.'; end if;
  if p_type not in ('PR','PO','GR','IV','PAY','SO','DL','BI','RC') then raise exception 'Loại chứng từ % không tồn tại.', p_type; end if;
  if u.is_admin then
    if r <> 'GV' and r <> erp_type_role(p_type) then raise exception 'Vai trò % không được lập loại chứng từ này (SU53).', r; end if;
  else
    r := erp_role_for(u, p_type);
    if r is null then
      raise exception 'Bạn chưa được giao quyền lập loại chứng từ này (SU53). Nhờ giảng viên giao kiêm nhiệm nếu nhóm thiếu người.';
    end if;
  end if;
  -- Bất biến 1: trường bút toán và trường do máy chủ tính đều bị bỏ, không tin trình duyệt
  b := b - 'je' - 'status' - 'net' - 'vat' - 'total' - 'value' - 'invNo' - 'blockReason' - 'jeNo' - 'hist' - 'by' - 'at' - 'no' - 'seq' - 'type';
  d := erp_date(b->>'date');
  select v into cfg from erp_cfg where k = 'main';
  tol := coalesce((cfg->>'tol')::numeric, 5);

  perform pg_advisory_xact_lock(hashtext('erp:doc:' || p_co));

  if p_type in ('PR','SO') then
    if jsonb_typeof(b->'items') <> 'array' or jsonb_array_length(b->'items') = 0 then raise exception 'Chứng từ chưa có dòng hàng.'; end if;
    if p_type = 'SO' then
      select * into pa from erp_partner where co = p_co and code = b->>'cust' and kind = 'C' and active;
      if not found then raise exception 'Khách hàng không hợp lệ.'; end if;
      if coalesce(trim(b->>'custPo'),'') = '' then raise exception 'Thiếu số đơn đặt hàng của khách. Đơn bán phải có căn cứ.'; end if;
    else
      if coalesce(trim(b->>'reason'),'') = '' then raise exception 'Thiếu lý do đề nghị.'; end if;
    end if;
    for it in select * from jsonb_array_elements(b->'items') loop
      select * into m from erp_mat where co = p_co and code = it->>'mat' and active;
      if not found then raise exception 'Mã hàng % không có trong danh mục.', it->>'mat'; end if;
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
        b := b || jsonb_build_object('blockReason','Vượt hạn mức tín dụng ' || to_char(erp_exposure(p_co, pa.code) + total - pa.credit_lim,'FM999G999G999G999') || ' đồng');
        note := 'Kiểm tra tín dụng: vượt hạn mức';
      else st := 'approved'; note := 'Kiểm tra tín dụng: đạt'; end if;
    end if;

  elsif p_type = 'PO' then
    src := erp_doc_data(p_co, b->>'pr');
    if src is null or src->>'status' <> 'approved' then raise exception 'Đề nghị mua chưa được duyệt hoặc không tồn tại.'; end if;
    if exists (select 1 from erp_doc where co = p_co and type = 'PO' and status <> 'rejected' and data->>'pr' = b->>'pr') then
      raise exception 'Đề nghị mua này đã được lập đơn mua.'; end if;
    select * into pa from erp_partner where co = p_co and code = b->>'vendor' and kind = 'V' and active;
    if not found then raise exception 'Nhà cung cấp không hợp lệ.'; end if;
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
      if q <> trunc(q) then raise exception 'Số lượng phải là số nguyên.'; end if;
      rem := erp_num(src->'items'->i,'qty') - erp_kid_qty(p_co,'GR','po',b->>'po',i);
      if q > rem then raise exception 'Nhập vượt đơn mua: % chỉ còn % cần nhận. Hàng giao thừa phải lập biên bản và trả lại NCC.', src->'items'->i->>'mat', rem; end if;
      pr := erp_num(src->'items'->i,'price');
      items := items || jsonb_build_object('line',i,'mat',src->'items'->i->>'mat','qty',q,'price',pr);
      je := je || jsonb_build_object('a',(select acc from erp_mat where co=p_co and code=src->'items'->i->>'mat'),'dr',q*pr,'mat',src->'items'->i->>'mat','q',q);
      net := net + q*pr;
    end loop;
    if jsonb_array_length(items) = 0 then raise exception 'Chưa có số lượng thực nhận.'; end if;
    je := je || jsonb_build_object('a',erp_ad('AP'),'cr',net,'p',src->>'vendor');
    b := b || jsonb_build_object('items',items,'vendor',src->>'vendor','value',net);
    st := 'posted';

  elsif p_type = 'IV' then
    src := erp_doc_data(p_co, b->>'po');
    if src is null or src->>'status' <> 'approved' then raise exception 'Đơn mua chưa được duyệt hoặc không tồn tại.'; end if;
    -- invNo đã bị bỏ khỏi b ở trên (vì với hóa đơn bán máy chủ tự cấp); với hóa đơn mua đọc lại từ p_body
    b := b || jsonb_build_object('invSym', upper(trim(coalesce(p_body->>'invSym',''))), 'invNo', trim(coalesce(p_body->>'invNo','')));
    if b->>'invSym' = '' or b->>'invNo' = '' then raise exception 'Thiếu ký hiệu hoặc số hóa đơn.'; end if;
    if exists (select 1 from erp_doc where co = p_co and type = 'IV' and status <> 'rejected' and data->>'vendor' = src->>'vendor'
               and upper(data->>'invSym') = b->>'invSym' and ltrim(data->>'invNo','0') = ltrim(b->>'invNo','0')) then
      raise exception 'Hóa đơn trùng: hóa đơn %/% của nhà cung cấp này đã được ghi nhận.', b->>'invSym', b->>'invNo'; end if;
    for it in select * from jsonb_array_elements(coalesce(b->'items','[]')) loop
      i := (it->>'line')::int; q := erp_num(it,'qty'); pr := round(coalesce(erp_num(it,'price'),0));
      if i is null or i < 0 or i >= jsonb_array_length(src->'items') then raise exception 'Dòng đơn mua không hợp lệ.'; end if;
      if q is null or q <= 0 then continue; end if;
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
      raise exception 'Số liệu không cân: tổng trên hóa đơn % khác số hệ thống tính %.', erp_num(p_body,'gross'), total; end if;
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
    if amt <= 0 or amt > rem then raise exception 'Số tiền không hợp lệ: chỉ được đề nghị tối đa %.', rem; end if;
    if b->>'acc' not in (erp_ad('CASH'), erp_ad('BANK')) then raise exception 'Tài khoản chi phải là % hoặc %.', erp_ad('CASH'), erp_ad('BANK'); end if;
    b := b || jsonb_build_object('vendor',src->>'vendor','amount',amt);
    st := 'pending';

  elsif p_type = 'DL' then
    src := erp_doc_data(p_co, b->>'so');
    if src is null or src->>'status' <> 'approved' then raise exception 'Đơn bán chưa được xác nhận.'; end if;
    if coalesce(trim(b->>'receiver'),'') = '' then raise exception 'Thiếu người nhận hàng.'; end if;
    for it in select * from jsonb_array_elements(coalesce(b->'items','[]')) loop
      i := (it->>'line')::int; q := erp_num(it,'qty');
      if i is null or i < 0 or i >= jsonb_array_length(src->'items') then raise exception 'Dòng đơn bán không hợp lệ.'; end if;
      if q is null or q <= 0 then continue; end if;
      if q <> trunc(q) then raise exception 'Số lượng phải là số nguyên.'; end if;
      rem := erp_num(src->'items'->i,'qty') - erp_kid_qty(p_co,'DL','so',b->>'so',i);
      if q > rem then raise exception 'Xuất vượt đơn bán: % chỉ còn %.', src->'items'->i->>'mat', rem; end if;
      cost := erp_val_out(p_co, src->'items'->i->>'mat', q);
      items := items || jsonb_build_object('line',i,'mat',src->'items'->i->>'mat','qty',q,'cost',cost);
      je := je || jsonb_build_object('a',(select acc from erp_mat where co=p_co and code=src->'items'->i->>'mat'),'cr',cost,'mat',src->'items'->i->>'mat','q',q);
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
    rem := erp_num(src,'total') - erp_kid_amt(p_co,'RC','bi',b->>'bi');
    if amt <= 0 or amt > rem then raise exception 'Số tiền không hợp lệ: tối đa %.', rem; end if;
    if coalesce(trim(b->>'ref'),'') = '' then raise exception 'Thiếu số giấy báo Có hoặc người nộp tiền.'; end if;
    if b->>'acc' not in (erp_ad('CASH'), erp_ad('BANK')) then raise exception 'Tài khoản thu phải là % hoặc %.', erp_ad('CASH'), erp_ad('BANK'); end if;
    b := b || jsonb_build_object('cust',src->>'cust','amount',amt,'memo','Thu tiền hóa đơn ' || (src->>'invSym') || ' số ' || (src->>'invNo'));
    st := 'pending';
  end if;

  select coalesce(max(seq),0) + 1 into s from erp_doc where co = p_co and type = p_type;
  pre := case p_type when 'PR' then '100000' when 'PO' then '450000' when 'GR' then '500000' when 'IV' then '510000'
                     when 'PAY' then '150000' when 'SO' then '000010' when 'DL' then '800000' when 'BI' then '900000'
                     when 'RC' then '140000' end;
  v_id := p_type || lpad(s::text, 5, '0');
  v_no := pre || lpad(s::text, 4, '0');
  if p_type = 'BI' then b := b || jsonb_build_object('invNo', lpad(s::text, 8, '0')); end if;
  if p_type in ('GR','IV','DL','BI') then
    posted := erp_post(p_co, v_id, p_type, d, u.id, je, '');
    b := b || jsonb_build_object('je', posted->'lines', 'jeNo', posted->>'je');
    -- Cập nhật định giá kho cho phần nhập và chênh lệch giá (phần xuất đã cập nhật trong erp_val_out)
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

-- ---------- Phê duyệt (PAY, RC ghi sổ qua erp_post) ----------
create or replace function erp_doc_decide(p_token text, p_co text, p_id text, p_ok boolean, p_note text, p_act_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u erp_user; r text; d erp_doc; ns text; nd jsonb; ts text := erp_iso(); acc text; amt numeric; bal numeric; posted jsonb;
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
  perform pg_advisory_xact_lock(hashtext('erp:doc:' || p_co));
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
    if d.type = 'IV' then raise exception 'Hóa đơn đã ghi sổ không hủy bằng từ chối. Hãy gỡ khóa sau khi NCC điều chỉnh, hoặc lập bút toán điều chỉnh (từ P4).'; end if;
  elsif d.type in ('PAY','RC') then
    acc := d.data->>'acc'; amt := (d.data->>'amount')::numeric;
    if acc not in (erp_ad('CASH'), erp_ad('BANK')) then raise exception 'Tài khoản tiền không hợp lệ.'; end if;
    if d.type = 'PAY' then
      bal := erp_balance(p_co, acc);
      if bal < amt then raise exception 'Không đủ số dư TK % (còn % đồng).', acc, to_char(bal,'FM999G999G999G999'); end if;
      posted := erp_post(p_co, d.id, 'PAY', erp_date(d.data->>'date'), u.id,
        jsonb_build_array(jsonb_build_object('a',erp_ad('AP'),'dr',amt,'p',d.data->>'vendor'), jsonb_build_object('a',acc,'cr',amt)), '');
    else
      posted := erp_post(p_co, d.id, 'RC', erp_date(d.data->>'date'), u.id,
        jsonb_build_array(jsonb_build_object('a',acc,'dr',amt), jsonb_build_object('a',erp_ad('AR'),'cr',amt,'p',d.data->>'cust')), '');
    end if;
    ns := 'posted';
    nd := nd || jsonb_build_object('je', posted->'lines', 'jeNo', posted->>'je', 'postDate', ts);
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

-- ---------- Đồng bộ: thêm danh mục tài khoản ----------
create or replace function erp_sync(p_token text, p_co text, p_since timestamptz) returns jsonb language plpgsql
security definer set search_path = public, extensions as $$
declare u erp_user; v_co text := p_co; v_docs jsonb; v_users jsonb; v_now timestamptz := clock_timestamp(); v_acc jsonb;
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
  if p_since is null then
    select jsonb_object_agg(code, jsonb_build_object('n',name,'k',kind,'r',recon,'ph',from_phase)) into v_acc from erp_acct where active;
  end if;
  return jsonb_build_object(
    'now', v_now,
    'me', erp_user_json(u),
    'cfg', (select v from erp_cfg where k = 'main'),
    'epochs', (select v from erp_cfg where k = 'epoch'),
    'users', v_users,
    'accts', v_acc,
    'docs', v_docs);
end $$;

-- ---------- Tham số: thêm thuế suất GTGT ----------
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
