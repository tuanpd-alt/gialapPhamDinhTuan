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
  select (p_obj in ('VEN','CUS') and p_field in ('bank_acc','bank_name','credit_lim','terms','active'))
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
      insert into erp_md_change(co,obj,key,field,old_val,new_val,status,by) values (p_co,p_obj,k,'*tạo mới',null,trim(p_data->>'name'),'pending',u.id);
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
