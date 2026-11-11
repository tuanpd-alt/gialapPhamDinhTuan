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
