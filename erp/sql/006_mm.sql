-- =====================================================================
-- ERP Lab 2.0 – P4: Mua hàng và kho nâng cao
-- Hỏi giá – báo giá (ME41/ME47/ME49); đơn mua theo báo giá, duyệt 2 cấp theo giá trị, cảnh báo chia nhỏ đơn (ME21N/ME29N);
-- MIGO 122 trả hàng NCC, 311 chuyển kho, 201 xuất dùng cho trung tâm chi phí, 551 hủy hàng hỏng; dung sai số lượng 101;
-- MIRO nhiều mã thuế, phân bổ chi phí vận chuyển, chặn trùng hóa đơn theo MST; giấy báo có của NCC khi trả hàng đã có hóa đơn;
-- F-48 ứng trước NCC theo đơn mua, tự bù trừ khi có hóa đơn; chiết khấu thanh toán sớm; F110 đợt thanh toán;
-- MI01/MI04/MI07 kiểm kê, đóng băng tồn.
-- Chạy sau 005_gl_cash.sql. Chạy lại nhiều lần an toàn; không xóa dữ liệu.
-- =====================================================================

-- ---------- Dữ liệu gốc, tham số ----------
alter table erp_partner add column if not exists disc_pct numeric not null default 0;   -- % chiết khấu thanh toán sớm
alter table erp_partner add column if not exists disc_days int not null default 0;      -- số ngày được hưởng chiết khấu
-- Mẫu: NCC01 cho hưởng 2% nếu trả trong 10 ngày (điều khoản "2/10, net 30"); chỉ đặt khi chưa có
update erp_partner set disc_pct = 2, disc_days = 10 where code = 'NCC01' and kind = 'V' and disc_pct = 0 and disc_days = 0;

insert into erp_acct_det(k,acc,note) values
 ('PAY_DISC','515','Chiết khấu thanh toán được hưởng khi trả NCC sớm'),
 ('SCRAP','632','Hàng tồn kho hư hỏng, mất mát sau khi trừ bồi thường'),
 ('INV_SHORT','1381','Hàng tồn kho thiếu khi kiểm kê, chờ xử lý'),
 ('INV_OVER','3381','Hàng tồn kho thừa khi kiểm kê, chờ giải quyết')
on conflict (k) do update set acc = excluded.acc, note = excluded.note;

-- poAuto = hạn mức A (tự duyệt), poB = hạn mức B (trên B cần Giám đốc), grTol = dung sai số lượng nhận (%)
update erp_cfg set v = v || '{"poB":500000000}'::jsonb where k = 'main' and not (v ? 'poB');
update erp_cfg set v = v || '{"grTol":2}'::jsonb where k = 'main' and not (v ? 'grTol');

-- Quyền P4
insert into erp_role_perm(role,tc,act) select r, tc, a from (values
 ('MH','ME41','C'),('MH','ME47','C'),('MH','ME49','V'),('MH','ZMMR','V'),
 ('KHO','MI01','C'),('KHO','MI07','C'),('KHO','ZMMR','V'),('KHO','ME49','V'),
 ('AP','F110','C'),('AP','F-48','C'),('AP','ZMMR','V'),('KT','F110','C'),('KT','F-48','C'),('KT','ZMMR','V'),
 ('KTT','ME41','V'),('KTT','ME49','V'),('KTT','MI01','V'),('KTT','MI07','A'),('KTT','F110','A'),('KTT','ZMMR','V'),
 ('GD','ME29N','A'),('GD','F110','A'),('GD','ME49','V'),('GD','ZMMR','V'),('GD','MI01','V'),
 ('KSNB','ME49','V'),('KSNB','MI01','V'),('KSNB','ZMMR','V'),('KSNB','F110','V')
) as p(r,tc,a) on conflict do nothing;

create or replace function erp_type_tc(p_type text) returns text language sql immutable set search_path = public, extensions as $$
  select case p_type when 'PR' then 'ME51N' when 'PO' then 'ME21N' when 'GR' then 'MIGO' when 'IV' then 'MIRO' when 'PAY' then 'F-53'
                     when 'SO' then 'VA01' when 'DL' then 'VL01N' when 'BI' then 'VF01' when 'RC' then 'F-28'
                     when 'JE' then 'FB50' when 'CJ' then 'FBCJ' when 'CNT' then 'ZKQ' when 'ADV' then 'ZTU' when 'ADS' then 'ZTU'
                     when 'RFQ' then 'ME41' when 'QT' then 'ME47' when 'RTV' then 'MIGO' when 'TRF' then 'MIGO' when 'GI' then 'MIGO'
                     when 'SCR' then 'MIGO' when 'CM' then 'MIRO' when 'PRUN' then 'F110' when 'PI' then 'MI01' end
$$;
create or replace function erp_type_role(p_type text) returns text language sql immutable set search_path = public, extensions as $$
  select case p_type when 'PR' then 'KHO' when 'GR' then 'KHO' when 'DL' then 'KHO' when 'PO' then 'MH' when 'SO' then 'KD'
                     when 'IV' then 'AP' when 'PAY' then 'AP' when 'BI' then 'AR' when 'RC' then 'AR'
                     when 'JE' then 'TH' when 'CJ' then 'TH' when 'CNT' then 'TQ'
                     when 'RFQ' then 'MH' when 'QT' then 'MH' when 'RTV' then 'KHO' when 'TRF' then 'KHO' when 'GI' then 'KHO'
                     when 'SCR' then 'KHO' when 'CM' then 'AP' when 'PRUN' then 'AP' when 'PI' then 'KHO' end
$$;

-- ---------- Kiểm kê: đóng băng tồn ----------
create or replace function erp_pi_frozen(p_co text, p_mat text) returns boolean language sql stable set search_path = public, extensions as $$
  select exists (select 1 from erp_doc d, jsonb_array_elements(d.data->'items') it
                  where d.co = p_co and d.type = 'PI' and d.status in ('open','counted','pending') and it->>'mat' = p_mat)
$$;
-- Ghi tăng/giảm tồn: chặn biến động số lượng của vật tư đang kiểm kê (trừ chính bút toán kiểm kê)
create or replace function erp_val_in(p_co text, p_mat text, p_qty numeric, p_value numeric) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_qty <> 0 and coalesce(current_setting('erp.pi_post', true),'') <> 'on' and erp_pi_frozen(p_co, p_mat) then
    raise exception 'Vật tư % đang kiểm kê (MI01): tồn kho bị đóng băng đến khi ghi sổ chênh lệch kiểm kê (MI07).', p_mat; end if;
  insert into erp_val(co,mat,qty,value) values (p_co,p_mat,p_qty,p_value)
  on conflict (co,mat) do update set qty = erp_val.qty + excluded.qty, value = erp_val.value + excluded.value;
end $$;
create or replace function erp_val_out(p_co text, p_mat text, p_qty numeric) returns numeric
language plpgsql security definer set search_path = public, extensions as $$
declare v erp_val; cost numeric;
begin
  if coalesce(current_setting('erp.pi_post', true),'') <> 'on' and erp_pi_frozen(p_co, p_mat) then
    raise exception 'Vật tư % đang kiểm kê (MI01): tồn kho bị đóng băng đến khi ghi sổ chênh lệch kiểm kê (MI07).', p_mat; end if;
  select * into v from erp_val where co = p_co and mat = p_mat for update;
  if not found or v.qty < p_qty then
    raise exception 'Không đủ tồn kho %: còn % trong kho. Báo Thủ kho lập đề nghị mua (ME51N).', p_mat, coalesce(v.qty,0);
  end if;
  cost := case when v.qty = p_qty then v.value else round(v.value / v.qty * p_qty) end;
  update erp_val set qty = qty - p_qty, value = value - cost where co = p_co and mat = p_mat;
  return cost;
end $$;

-- Tồn theo kho (storage location): tính từ chứng từ. DL, OB, kiểm kê dùng kho mặc định của vật tư.
create or replace function erp_sloc_qty(p_co text, p_mat text, p_sloc text) returns numeric language sql stable set search_path = public, extensions as $$
  select coalesce((select m.open_qty from erp_mat m where m.co = p_co and m.code = p_mat and m.sloc = p_sloc
                    and exists (select 1 from erp_doc where co = p_co and type = 'OB')),0)
   + coalesce((select sum(case
        when d.type = 'GR' and coalesce(it->>'sloc', m.sloc) = p_sloc then (it->>'qty')::numeric
        when d.type in ('RTV','GI','SCR') and coalesce(it->>'sloc', m.sloc) = p_sloc then -(it->>'qty')::numeric
        when d.type = 'DL' and coalesce(it->>'sloc', m.sloc) = p_sloc then -(it->>'qty')::numeric
        when d.type = 'TRF' and it->>'to' = p_sloc then (it->>'qty')::numeric
        when d.type = 'TRF' and it->>'from' = p_sloc then -(it->>'qty')::numeric
        when d.type = 'PI' and m.sloc = p_sloc then coalesce((it->>'diff')::numeric,0)
        else 0 end)
      from erp_doc d cross join lateral jsonb_array_elements(d.data->'items') it
      join erp_mat m on m.co = d.co and m.code = it->>'mat'
     where d.co = p_co and it->>'mat' = p_mat and d.status = 'posted' and d.type in ('GR','RTV','GI','SCR','DL','TRF','PI')),0)
$$;

-- Số lượng đã nhận thuần theo dòng đơn mua (nhập 101 trừ trả 122)
create or replace function erp_po_recv(p_co text, p_po text, p_line int) returns numeric language sql stable set search_path = public, extensions as $$
  select erp_kid_qty(p_co,'GR','po',p_po,p_line) - erp_kid_qty(p_co,'RTV','po',p_po,p_line)
$$;
-- Số đã thanh toán (gồm chiết khấu được hưởng) cho một hóa đơn
create or replace function erp_iv_settled(p_co text, p_iv text) returns numeric language sql stable set search_path = public, extensions as $$
  select coalesce(sum(coalesce((data->>'settle')::numeric,(data->>'amount')::numeric)),0) from erp_doc
   where co = p_co and type = 'PAY' and status in ('pending','approved','posted') and data->>'iv' = p_iv
$$;
-- Phần ứng trước theo đơn mua chưa bù trừ vào hóa đơn
create or replace function erp_dp_open(p_co text, p_po text) returns numeric language sql stable set search_path = public, extensions as $$
  select coalesce((select sum((data->>'amount')::numeric) from erp_doc where co = p_co and type = 'PAY' and status = 'posted'
                    and data->>'kind' = 'dp' and data->>'po' = p_po),0)
       - coalesce((select sum((data->>'dpAlloc')::numeric) from erp_doc where co = p_co and type = 'IV' and status <> 'rejected'
                    and data->>'po' = p_po),0)
$$;
-- Mức duyệt đơn mua: 0 tự duyệt, 1 KTT, 2 KTT rồi Giám đốc
create or replace function erp_po_level(p_total numeric) returns int language sql stable set search_path = public, extensions as $$
  select case when coalesce((v->>'poAuto')::numeric,0) > 0 and p_total <= (v->>'poAuto')::numeric then 0
              when coalesce((v->>'poB')::numeric,0) > 0 and p_total > (v->>'poB')::numeric then 2 else 1 end
    from erp_cfg where k = 'main'
$$;
create or replace function erp_tax_ok(p numeric) returns boolean language sql immutable as $$ select p in (0,5,8,10) $$;

-- ---------- Lập chứng từ P4 (gọi từ erp_doc_create) ----------
create or replace function erp_mm_create(u erp_user, r text, v_roles text[], p_co text, p_type text, p_body jsonb, p_note text, d date)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  b jsonb := p_body; src jsonb; it jsonb; x jsonb; items jsonb := '[]'; je jsonb := '[]'; st text; note text := coalesce(p_note,'');
  q numeric; pr numeric; i int; n int; net numeric := 0; vat numeric := 0; total numeric; rate numeric := erp_vat(); tx numeric;
  cfg jsonb; tol numeric; m erp_mat; pa erp_partner; rem numeric; diff numeric; diffsum numeric := 0; bad text := '';
  cost numeric; costsum numeric := 0; amt numeric; s int; v_id text; v_no text; pre text; ts text := erp_iso(); posted jsonb;
  fr numeric; frvat numeric := 0; frtax numeric; alloc numeric; acc_left numeric; best numeric; mine numeric; lvl int; lvls int; ssum numeric;
  rfq jsonb; qt jsonb; iv jsonb; ivline jsonb; disc numeric := 0; vlist text[]; tsum numeric := 0; rt text; dpa numeric;
begin
  select v into cfg from erp_cfg where k = 'main';
  tol := coalesce((cfg->>'tol')::numeric, 5);
  -- Trường do máy chủ quyết định: không nhận từ trình duyệt
  b := b - 'level' - 'splitWarn' - 'notCheapest' - 'bestNet' - 'dpAlloc' - 'settle' - 'disc' - 'discUntil' - 'discPct' - 'discDays'
         - 'kind' - 'run' - 'runNo' - 'decBy' - 'decAt' - 'dec2By' - 'pays' - 'short' - 'over' - 'credit' - 'freightVat' - 'mvt';
  if p_type = 'PO' then b := b - 'rfq'; end if;

  if p_type = 'RFQ' then   -- ME41 yêu cầu báo giá
    src := erp_doc_data(p_co, b->>'pr');
    if src is null or src->>'status' <> 'approved' then raise exception 'Đề nghị mua chưa được duyệt hoặc không tồn tại.'; end if;
    if exists (select 1 from erp_doc where co = p_co and type = 'PO' and status <> 'rejected' and data->>'pr' = b->>'pr') then
      raise exception 'Đề nghị mua này đã được lập đơn mua.'; end if;
    if exists (select 1 from erp_doc where co = p_co and type = 'RFQ' and status <> 'rejected' and data->>'pr' = b->>'pr') then
      raise exception 'Đề nghị mua này đã có yêu cầu báo giá. Nhập báo giá ở ME47.'; end if;
    if jsonb_typeof(b->'vendors') <> 'array' or jsonb_array_length(b->'vendors') < 3 then
      raise exception 'Gửi yêu cầu báo giá cho ít nhất 3 nhà cung cấp để so sánh (quy chế mua hàng).'; end if;
    for x in select * from jsonb_array_elements(b->'vendors') loop
      select * into pa from erp_partner where co = p_co and code = x#>>'{}' and kind = 'V';
      if not found then raise exception 'Nhà cung cấp % không hợp lệ.', x#>>'{}'; end if;
      if not pa.active or not pa.confirmed then raise exception 'Nhà cung cấp % đang khóa hoặc chưa được KTT xác nhận.', pa.code; end if;
      if pa.code = any(vlist) then raise exception 'Nhà cung cấp % bị chọn trùng.', pa.code; end if;
      vlist := vlist || pa.code;
    end loop;
    b := jsonb_build_object('pr', b->>'pr', 'date', to_char(d,'YYYY-MM-DD'), 'vendors', to_jsonb(vlist), 'items', src->'items',
           'due', coalesce(nullif(b->>'due',''), to_char(d + 5,'YYYY-MM-DD')), 'memo', coalesce(b->>'memo',''));
    st := 'open'; pre := '600000';

  elsif p_type = 'QT' then   -- ME47 nhập báo giá
    rfq := erp_doc_data(p_co, b->>'rfq');
    if rfq is null or rfq->>'status' <> 'open' then raise exception 'Yêu cầu báo giá không còn mở.'; end if;
    if not (rfq->'vendors' ? (b->>'vendor')) then raise exception 'Nhà cung cấp % không nằm trong danh sách được hỏi giá.', b->>'vendor'; end if;
    if exists (select 1 from erp_doc where co = p_co and type = 'QT' and status <> 'rejected' and data->>'rfq' = b->>'rfq' and data->>'vendor' = b->>'vendor') then
      raise exception 'Đã nhập báo giá của nhà cung cấp % cho yêu cầu này.', b->>'vendor'; end if;
    if jsonb_typeof(b->'items') <> 'array' or jsonb_array_length(b->'items') <> jsonb_array_length(rfq->'items') then
      raise exception 'Báo giá phải có giá cho đủ các dòng của yêu cầu báo giá.'; end if;
    for i in 0 .. jsonb_array_length(rfq->'items') - 1 loop
      pr := round(coalesce(erp_num(b->'items'->i,'price'),0));
      if pr <= 0 then raise exception 'Dòng %: đơn giá phải lớn hơn 0.', i+1; end if;
      q := erp_num(rfq->'items'->i,'qty'); net := net + q*pr;
      items := items || jsonb_build_object('mat', rfq->'items'->i->>'mat', 'qty', q, 'price', pr);
    end loop;
    select * into pa from erp_partner where co = p_co and code = b->>'vendor';
    b := jsonb_build_object('rfq', b->>'rfq', 'pr', rfq->>'pr', 'vendor', pa.code, 'date', to_char(d,'YYYY-MM-DD'), 'items', items,
           'net', net, 'vat', round(net*rate), 'total', net + round(net*rate),
           'lead', greatest(coalesce(erp_num(b,'lead'),0),0)::int, 'terms', coalesce(erp_num(b,'terms'), pa.terms)::int,
           'validTo', coalesce(nullif(b->>'validTo',''), to_char(d + 30,'YYYY-MM-DD')), 'ref', coalesce(b->>'ref',''));
    st := 'posted'; pre := '610000';

  elsif p_type = 'PO' then   -- ME21N (thay nhánh P1): theo báo giá nếu đề nghị mua đã hỏi giá; duyệt theo hạn mức
    src := erp_doc_data(p_co, b->>'pr');
    if src is null or src->>'status' <> 'approved' then raise exception 'Đề nghị mua chưa được duyệt hoặc không tồn tại.'; end if;
    if exists (select 1 from erp_doc where co = p_co and type = 'PO' and status <> 'rejected' and data->>'pr' = b->>'pr') then
      raise exception 'Đề nghị mua này đã được lập đơn mua.'; end if;
    select data into rfq from erp_doc where co = p_co and type = 'RFQ' and status = 'open' and data->>'pr' = b->>'pr';
    if rfq is not null and coalesce(b->>'qt','') = '' then
      raise exception 'Đề nghị mua này đã hỏi giá (ME41). Chọn một báo giá ở ME49 để lập đơn mua.'; end if;
    if coalesce(b->>'qt','') <> '' then
      qt := erp_doc_data(p_co, b->>'qt');
      if qt is null or qt->>'type' <> 'QT' or qt->>'pr' <> b->>'pr' then raise exception 'Báo giá không thuộc đề nghị mua này.'; end if;
      if (qt->>'validTo')::date < d then raise exception 'Báo giá đã hết hiệu lực (%).', qt->>'validTo'; end if;
      if (select count(*) from erp_doc where co = p_co and type = 'QT' and status <> 'rejected' and data->>'rfq' = qt->>'rfq') < 2 then
        raise exception 'Cần ít nhất 2 báo giá để so sánh trước khi chọn nhà cung cấp.'; end if;
      select min((data->>'net')::numeric) into best from erp_doc where co = p_co and type = 'QT' and status <> 'rejected' and data->>'rfq' = qt->>'rfq';
      if (qt->>'net')::numeric > best and length(coalesce(trim(b->>'reason'),'')) < 10 then
        raise exception 'Báo giá được chọn không phải giá thấp nhất (thấp nhất % đồng). Ghi lý do chọn (chất lượng, thời hạn giao, điều khoản…), tối thiểu 10 ký tự.', erp_fm(best); end if;
      b := b || jsonb_build_object('vendor', qt->>'vendor', 'items', qt->'items', 'rfq', qt->>'rfq',
                                   'notCheapest', (qt->>'net')::numeric > best, 'bestNet', best);
    end if;
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
    lvl := erp_po_level(total);
    -- Cảnh báo chia nhỏ đơn: cùng NCC, cùng người lập, trong 3 ngày, tổng nhảy lên mức duyệt cao hơn
    select coalesce(sum((data->>'total')::numeric),0) into ssum from erp_doc
     where co = p_co and type = 'PO' and status <> 'rejected' and data->>'vendor' = pa.code and data->>'by' = u.id::text
       and abs((data->>'date')::date - d) <= 3;
    lvls := erp_po_level(ssum + total);
    b := b || jsonb_build_object('items',items,'net',net,'vat',vat,'total',total,'vatRate',rate,'terms',pa.terms,'level',lvl);
    if ssum > 0 and lvls > lvl then
      b := b || jsonb_build_object('splitWarn', 'Cảnh báo chia nhỏ đơn: cùng NCC ' || pa.code || ', cùng người lập, trong 3 ngày đã có '
               || erp_fm(ssum) || ' đồng; cộng đơn này ' || erp_fm(ssum + total) || ' đồng thuộc mức duyệt ' || lvls || '.');
      if lvl = 0 then lvl := 1; b := b || jsonb_build_object('level', 1); end if;   -- không cho tự duyệt khi nghi chia nhỏ
    end if;
    if lvl = 0 then st := 'approved'; note := 'Tự duyệt do giá trị dưới hạn mức A'; else st := 'pending'; end if;
    if rfq is not null then update erp_doc set status = 'closed', data = data || '{"status":"closed"}' where co = p_co and type = 'RFQ' and data->>'pr' = b->>'pr' and status = 'open'; end if;
    pre := '450000';

  elsif p_type = 'IV' then   -- MIRO (thay nhánh P1)
    src := erp_doc_data(p_co, b->>'po');
    if src is null or src->>'status' <> 'approved' then raise exception 'Đơn mua chưa được duyệt hoặc không tồn tại.'; end if;
    select * into pa from erp_partner where co = p_co and code = src->>'vendor';
    b := b || jsonb_build_object('invSym', upper(trim(coalesce(p_body->>'invSym',''))), 'invNo', trim(coalesce(p_body->>'invNo','')));
    if b->>'invSym' = '' or b->>'invNo' = '' then raise exception 'Thiếu ký hiệu hoặc số hóa đơn.'; end if;
    -- Chặn trùng theo MST người bán (kể cả khi cùng một người bán bị tạo hai mã NCC)
    if exists (select 1 from erp_doc dd join erp_partner pp on pp.co = dd.co and pp.code = dd.data->>'vendor'
                where dd.co = p_co and dd.type = 'IV' and dd.status <> 'rejected' and (pp.code = pa.code or (pa.mst <> '' and pp.mst = pa.mst))
                  and upper(dd.data->>'invSym') = b->>'invSym' and ltrim(dd.data->>'invNo','0') = ltrim(b->>'invNo','0')) then
      raise exception 'Hóa đơn trùng: hóa đơn %/% của người bán MST % đã được ghi nhận.', b->>'invSym', b->>'invNo', pa.mst; end if;
    for it in select * from jsonb_array_elements(coalesce(b->'items','[]')) loop
      i := (it->>'line')::int; q := erp_num(it,'qty'); pr := round(coalesce(erp_num(it,'price'),0));
      tx := coalesce(erp_num(it,'tax'), round(rate*100));
      if i is null or i < 0 or i >= jsonb_array_length(src->'items') then raise exception 'Dòng đơn mua không hợp lệ.'; end if;
      if q is null or q <= 0 then continue; end if;
      if items @> jsonb_build_array(jsonb_build_object('line', i)) then
        raise exception 'Dòng % bị lặp trong cùng chứng từ. Gộp số lượng vào một dòng.', i+1; end if;
      if pr <= 0 then raise exception 'Đơn giá hóa đơn phải lớn hơn 0.'; end if;
      if not erp_tax_ok(tx) then raise exception 'Thuế suất % %% không hợp lệ (0, 5, 8, 10).', tx; end if;
      rem := erp_po_recv(p_co, b->>'po', i) - erp_kid_qty(p_co,'IV','po',b->>'po',i);
      if q > rem then raise exception 'Số lượng hóa đơn vượt số đã nhận thuần: % còn % chưa có hóa đơn (đã trừ hàng trả lại). Không ghi nhận hàng chưa về.', src->'items'->i->>'mat', rem; end if;
      diff := (pr - erp_num(src->'items'->i,'price')) * q;
      if abs(pr - erp_num(src->'items'->i,'price')) / erp_num(src->'items'->i,'price') * 100 > tol then
        bad := bad || case when bad = '' then '' else ', ' end || (src->'items'->i->>'mat'); end if;
      items := items || jsonb_build_object('line',i,'mat',src->'items'->i->>'mat','qty',q,'price',pr,'poPrice',erp_num(src->'items'->i,'price'),
                                           'tax',tx,'vat',round(q*pr*tx/100));
      net := net + q*pr; diffsum := diffsum + diff; vat := vat + round(q*pr*tx/100);
    end loop;
    n := jsonb_array_length(items);
    if n = 0 then raise exception 'Chưa có dòng nào trên hóa đơn.'; end if;
    -- Chi phí mua (vận chuyển) trên cùng hóa đơn: phân bổ vào giá nhập theo giá trị từng dòng
    fr := round(coalesce(erp_num(b,'freight'),0)); frtax := coalesce(erp_num(b,'freightTax'), round(rate*100));
    if fr < 0 then raise exception 'Chi phí vận chuyển không được âm.'; end if;
    if fr > 0 and not erp_tax_ok(frtax) then raise exception 'Thuế suất chi phí vận chuyển không hợp lệ.'; end if;
    acc_left := fr;
    for i in 0 .. n - 1 loop
      it := items->i;
      alloc := case when i = n - 1 then acc_left else round(fr * (it->>'qty')::numeric * (it->>'price')::numeric / net) end;
      acc_left := acc_left - alloc;
      diff := ((it->>'price')::numeric - (it->>'poPrice')::numeric) * (it->>'qty')::numeric;
      items := jsonb_set(items, array[i::text], it || jsonb_build_object('frAlloc', alloc));
      if diff + alloc <> 0 then
        je := je || jsonb_build_object('a',(select acc from erp_mat where co=p_co and code=it->>'mat'),
                     case when diff + alloc > 0 then 'dr' else 'cr' end, abs(diff + alloc),'mat',it->>'mat');
      end if;
    end loop;
    if fr > 0 then frvat := round(fr*frtax/100); vat := vat + frvat; end if;
    total := net + fr + vat;
    if erp_num(p_body,'gross') is not null and abs(erp_num(p_body,'gross') - total) > 1 then
      raise exception 'Số liệu không cân: tổng trên hóa đơn % khác số hệ thống tính %.', erp_fm(erp_num(p_body,'gross')), erp_fm(total); end if;
    if vat > 0 then je := je || jsonb_build_object('a',erp_ad('VAT_IN'),'dr',vat); end if;
    je := je || jsonb_build_object('a',erp_ad('AP'), case when diffsum + fr + vat >= 0 then 'cr' else 'dr' end, abs(diffsum + fr + vat),'p',src->>'vendor');
    dpa := least(greatest(erp_dp_open(p_co, b->>'po'),0), total);
    b := b || jsonb_build_object('items',items,'vendor',src->>'vendor','net',net,'freight',fr,'freightTax',frtax,'freightVat',frvat,
           'vat',vat,'total',total,'vatRate',rate,'due', to_char(d + pa.terms, 'YYYY-MM-DD'),'dpAlloc',dpa,
           'discPct',pa.disc_pct,'discDays',pa.disc_days,'discUntil', case when pa.disc_pct > 0 then to_char(d + pa.disc_days,'YYYY-MM-DD') end);
    if bad <> '' then st := 'blocked'; b := b || jsonb_build_object('blockReason','Lệch giá vượt ' || tol || '%: ' || bad);
    else st := 'posted'; end if;
    if dpa > 0 then note := 'Tự bù trừ ứng trước ' || erp_fm(dpa) || ' đồng'; end if;
    pre := '510000';

  elsif p_type = 'CM' then   -- Giấy báo có của NCC (hóa đơn điều chỉnh giảm) cho hàng đã có hóa đơn rồi trả lại
    x := erp_doc_data(p_co, b->>'rtv');
    if x is null or x->>'type' <> 'RTV' or x->>'status' <> 'posted' then raise exception 'Phiếu trả hàng không hợp lệ.'; end if;
    if exists (select 1 from erp_doc where co = p_co and type = 'CM' and status <> 'rejected' and data->>'rtv' = b->>'rtv') then
      raise exception 'Phiếu trả hàng này đã có giấy báo có của NCC.'; end if;
    if coalesce((select sum((y->>'cmQty')::numeric) from jsonb_array_elements(x->'items') y),0) <= 0 then
      raise exception 'Hàng trả lại chưa có hóa đơn: không cần giấy báo có (phiếu trả hàng đã ghi giảm phải trả).'; end if;
    b := b || jsonb_build_object('invSym', upper(trim(coalesce(p_body->>'invSym',''))), 'invNo', trim(coalesce(p_body->>'invNo','')));
    if b->>'invSym' = '' or b->>'invNo' = '' then raise exception 'Thiếu ký hiệu hoặc số hóa đơn điều chỉnh giảm của NCC.'; end if;
    for it in select * from jsonb_array_elements(x->'items') loop
      q := coalesce((it->>'cmQty')::numeric,0); if q <= 0 then continue; end if;
      select y into ivline from erp_doc dd, jsonb_array_elements(dd.data->'items') y
       where dd.co = p_co and dd.type = 'IV' and dd.status = 'posted' and dd.data->>'po' = x->>'po' and (y->>'line')::int = (it->>'line')::int
       order by dd.seq desc limit 1;
      if ivline is null then raise exception 'Không tìm thấy hóa đơn của dòng hàng trả lại.'; end if;
      pr := (ivline->>'price')::numeric; tx := (ivline->>'tax')::numeric;
      diff := (pr - (ivline->>'poPrice')::numeric) * q;
      if diff <> 0 then
        je := je || jsonb_build_object('a',(select acc from erp_mat where co=p_co and code=it->>'mat'),
                     case when diff > 0 then 'cr' else 'dr' end, abs(diff),'mat',it->>'mat');
      end if;
      vat := vat + round(q*pr*tx/100); net := net + q*pr; diffsum := diffsum + diff;
      items := items || jsonb_build_object('line',it->'line','mat',it->>'mat','qty',q,'price',pr,'poPrice',ivline->'poPrice','tax',tx,'diff',diff);
    end loop;
    if vat > 0 then je := je || jsonb_build_object('a',erp_ad('VAT_IN'),'cr',vat); end if;
    je := je || jsonb_build_object('a',erp_ad('AP'), case when diffsum + vat >= 0 then 'dr' else 'cr' end, abs(diffsum + vat),'p',x->>'vendor');
    b := b || jsonb_build_object('po',x->>'po','vendor',x->>'vendor','items',items,'net',net,'vat',vat,'total',diffsum + vat,'credit',net+vat);
    st := 'posted'; pre := '520000';

  elsif p_type = 'RTV' then   -- MIGO 122 trả hàng NCC
    src := erp_doc_data(p_co, b->>'po');
    if src is null or src->>'status' <> 'approved' then raise exception 'Đơn mua không hợp lệ.'; end if;
    if length(coalesce(trim(b->>'reason'),'')) < 5 then raise exception 'Ghi lý do trả hàng (hàng lỗi, sai quy cách…) và số biên bản.'; end if;
    for it in select * from jsonb_array_elements(coalesce(b->'items','[]')) loop
      i := (it->>'line')::int; q := erp_num(it,'qty');
      if i is null or i < 0 or i >= jsonb_array_length(src->'items') then raise exception 'Dòng đơn mua không hợp lệ.'; end if;
      if q is null or q <= 0 then continue; end if;
      if q <> trunc(q) then raise exception 'Số lượng phải là số nguyên.'; end if;
      if items @> jsonb_build_array(jsonb_build_object('line', i)) then raise exception 'Dòng % bị lặp.', i+1; end if;
      rem := erp_po_recv(p_co, b->>'po', i);
      if q > rem then raise exception 'Trả vượt số đã nhận: % chỉ còn % đã nhận chưa trả.', src->'items'->i->>'mat', rem; end if;
      select * into m from erp_mat where co = p_co and code = src->'items'->i->>'mat';
      pr := erp_num(src->'items'->i,'price');
      -- phần đã có hóa đơn trong số trả lại → cần giấy báo có của NCC (CM)
      amt := greatest(q - (rem - erp_kid_qty(p_co,'IV','po',b->>'po',i)), 0);
      perform erp_val_in(p_co, m.code, -q, -q*pr);
      if (select qty from erp_val where co = p_co and mat = m.code) < 0 then raise exception 'Không đủ tồn kho % để trả.', m.code; end if;
      items := items || jsonb_build_object('line',i,'mat',m.code,'qty',q,'price',pr,'sloc',coalesce(nullif(it->>'sloc',''),m.sloc),'cmQty',amt);
      je := je || jsonb_build_object('a',m.acc,'cr',q*pr,'mat',m.code,'q',q);
      net := net + q*pr;
    end loop;
    if jsonb_array_length(items) = 0 then raise exception 'Chưa có số lượng trả lại.'; end if;
    for it in select * from jsonb_array_elements(items) loop
      if erp_sloc_qty(p_co, it->>'mat', it->>'sloc') < (it->>'qty')::numeric then
        raise exception 'Kho % không đủ % để xuất trả.', it->>'sloc', it->>'mat'; end if;
    end loop;
    je := jsonb_build_array(jsonb_build_object('a',erp_ad('AP'),'dr',net,'p',src->>'vendor')) || je;
    b := b || jsonb_build_object('items',items,'vendor',src->>'vendor','value',net,'mvt','122');
    st := 'posted'; pre := '500000';

  elsif p_type = 'TRF' then   -- MIGO 311 chuyển kho (cùng nhà máy, không bút toán)
    if jsonb_typeof(b->'items') <> 'array' or jsonb_array_length(b->'items') = 0 then raise exception 'Chưa có dòng chuyển kho.'; end if;
    for it in select * from jsonb_array_elements(b->'items') loop
      select * into m from erp_mat where co = p_co and code = it->>'mat';
      if not found or m.mtype = 'DV' then raise exception 'Vật tư % không quản lý tồn kho.', it->>'mat'; end if;
      q := erp_num(it,'qty'); if q is null or q <= 0 or q <> trunc(q) then raise exception 'Số lượng phải là số nguyên lớn hơn 0.'; end if;
      if it->>'from' = it->>'to' then raise exception 'Kho đi và kho đến phải khác nhau.'; end if;
      if not exists (select 1 from erp_org where co = p_co and kind = 'SLOC' and code = it->>'from')
         or not exists (select 1 from erp_org where co = p_co and kind = 'SLOC' and code = it->>'to') then raise exception 'Mã kho không hợp lệ.'; end if;
      if erp_pi_frozen(p_co, m.code) then raise exception 'Vật tư % đang kiểm kê (MI01): không chuyển kho.', m.code; end if;
      if erp_sloc_qty(p_co, m.code, it->>'from') < q then
        raise exception 'Kho % chỉ còn % %.', it->>'from', erp_sloc_qty(p_co, m.code, it->>'from'), m.code; end if;
      items := items || jsonb_build_object('mat',m.code,'qty',q,'from',it->>'from','to',it->>'to');
    end loop;
    b := b || jsonb_build_object('items',items,'mvt','311');
    st := 'posted'; pre := '490000';

  elsif p_type in ('GI','SCR') then   -- MIGO 201 xuất dùng cho TTCP / 551 hủy hàng hỏng (chờ duyệt)
    if length(coalesce(trim(b->>'reason'),'')) < 5 then raise exception 'Ghi lý do xuất kho.'; end if;
    if p_type = 'GI' then
      perform erp_manual_line(p_co, b->>'acc', b->>'cc', false);
      if not (b->>'acc' ~ '^6') then raise exception 'Xuất dùng nội bộ ghi vào tài khoản chi phí (6xx).'; end if;
      if coalesce(b->>'cc','') = '' then raise exception 'Xuất dùng phải ghi trung tâm chi phí sử dụng.'; end if;
    end if;
    if jsonb_typeof(b->'items') <> 'array' or jsonb_array_length(b->'items') = 0 then raise exception 'Chưa có dòng xuất kho.'; end if;
    for it in select * from jsonb_array_elements(b->'items') loop
      select * into m from erp_mat where co = p_co and code = it->>'mat';
      if not found or m.mtype = 'DV' then raise exception 'Vật tư % không quản lý tồn kho.', it->>'mat'; end if;
      q := erp_num(it,'qty'); if q is null or q <= 0 or q <> trunc(q) then raise exception 'Số lượng phải là số nguyên lớn hơn 0.'; end if;
      if items @> jsonb_build_array(jsonb_build_object('mat', m.code)) then raise exception 'Trùng vật tư %.', m.code; end if;
      if erp_sloc_qty(p_co, m.code, coalesce(nullif(it->>'sloc',''), m.sloc)) < q then
        raise exception 'Kho % không đủ % (còn %).', coalesce(nullif(it->>'sloc',''), m.sloc), m.code, erp_sloc_qty(p_co, m.code, coalesce(nullif(it->>'sloc',''), m.sloc)); end if;
      if p_type = 'GI' then
        cost := erp_val_out(p_co, m.code, q); costsum := costsum + cost;
        je := je || jsonb_build_object('a',m.acc,'cr',cost,'mat',m.code,'q',q);
      else
        if (select qty from erp_val where co = p_co and mat = m.code) < q then raise exception 'Không đủ tồn kho %.', m.code; end if;
      end if;
      items := items || jsonb_build_object('mat',m.code,'qty',q,'sloc',coalesce(nullif(it->>'sloc',''), m.sloc),'cost',cost);
    end loop;
    if p_type = 'GI' then
      je := jsonb_build_array(jsonb_build_object('a',b->>'acc','dr',costsum,'cc',b->>'cc')) || je;
      b := b || jsonb_build_object('items',items,'value',costsum,'mvt','201'); st := 'posted'; pre := '491000';
    else
      b := b || jsonb_build_object('items',items,'mvt','551'); st := 'pending'; pre := '492000';
    end if;

  elsif p_type = 'PAY' then   -- F-53 thanh toán hóa đơn / F-48 ứng trước theo đơn mua (thay nhánh P1)
    if b->>'acc' not in (erp_ad('CASH'), erp_ad('BANK')) then raise exception 'Tài khoản chi phải là % hoặc %.', erp_ad('CASH'), erp_ad('BANK'); end if;
    amt := round(coalesce(erp_num(p_body,'amount'),0));
    if coalesce(b->>'po','') <> '' and coalesce(b->>'iv','') = '' then
      src := erp_doc_data(p_co, b->>'po');
      if src is null or src->>'type' <> 'PO' or src->>'status' <> 'approved' then raise exception 'Ứng trước phải theo đơn mua đã duyệt.'; end if;
      rem := (src->>'total')::numeric - coalesce((select sum((data->>'amount')::numeric) from erp_doc where co = p_co and type = 'PAY'
               and status <> 'rejected' and data->>'kind' = 'dp' and data->>'po' = b->>'po'),0);
      if amt <= 0 or amt > rem then raise exception 'Số tiền ứng trước không hợp lệ: tối đa % đồng (giá trị đơn mua còn chưa ứng).', erp_fm(rem); end if;
      select * into pa from erp_partner where co = p_co and code = src->>'vendor';
      b := b || jsonb_build_object('kind','dp','vendor',pa.code,'amount',amt,'settle',0,
                                   'memo', 'Ứng trước cho NCC theo đơn mua ' || (src->>'no'));
    else
      src := erp_doc_data(p_co, b->>'iv');
      if src is null or src->>'status' <> 'posted' then raise exception 'Hóa đơn chưa ghi sổ hoặc đang bị khóa thanh toán.'; end if;
      select * into pa from erp_partner where co = p_co and code = src->>'vendor';
      rem := (src->>'total')::numeric - erp_iv_settled(p_co, b->>'iv') - coalesce((src->>'dpAlloc')::numeric,0);
      if coalesce((b->>'useDisc')::boolean,false) then
        if coalesce((src->>'discPct')::numeric,0) <= 0 or d > (src->>'discUntil')::date then
          raise exception 'Hóa đơn không còn trong hạn hưởng chiết khấu thanh toán (hạn %).', coalesce(src->>'discUntil','không có'); end if;
        disc := round(rem * (src->>'discPct')::numeric / 100); amt := rem - disc;
      end if;
      if amt <= 0 or amt + disc > rem then raise exception 'Số tiền không hợp lệ: chỉ được đề nghị tối đa % đồng.', erp_fm(rem); end if;
      b := b || jsonb_build_object('vendor',pa.code,'amount',amt,'disc',disc,'settle',amt + disc);
      if disc > 0 then b := b || jsonb_build_object('discUntil', src->>'discUntil'); end if;
    end if;
    if not pa.active then raise exception 'Nhà cung cấp % đang bị khóa (XK02): không được đề nghị thanh toán.', pa.code; end if;
    if b->>'acc' = erp_ad('BANK') and coalesce(pa.bank_acc,'') = '' then
      raise exception 'Nhà cung cấp % chưa có tài khoản ngân hàng đã duyệt. Cập nhật ở XK02 và chờ Kế toán trưởng duyệt.', pa.code; end if;
    if b->>'acc' = erp_ad('BANK') then b := b || jsonb_build_object('bankAcc', pa.bank_acc, 'bankName', pa.bank_name); end if;
    st := 'pending'; pre := '150000';

  elsif p_type = 'PRUN' then   -- F110 đợt thanh toán: đề xuất danh sách hóa đơn đến hạn, chi qua ngân hàng
    if jsonb_typeof(b->'items') <> 'array' or jsonb_array_length(b->'items') = 0 then raise exception 'Đợt thanh toán chưa có hóa đơn.'; end if;
    for it in select * from jsonb_array_elements(b->'items') loop
      iv := erp_doc_data(p_co, it->>'iv');
      if iv is null or iv->>'type' <> 'IV' or iv->>'status' <> 'posted' then raise exception 'Hóa đơn % chưa ghi sổ hoặc đang bị khóa.', it->>'iv'; end if;
      if items @> jsonb_build_array(jsonb_build_object('iv', it->>'iv')) then raise exception 'Hóa đơn % bị chọn trùng.', iv->>'invNo'; end if;
      if exists (select 1 from erp_doc where co = p_co and type = 'PAY' and status in ('pending','approved') and data->>'iv' = it->>'iv')
         or exists (select 1 from erp_doc dd, jsonb_array_elements(dd.data->'items') y where dd.co = p_co and dd.type = 'PRUN'
                     and dd.status in ('pending','pending2') and y->>'iv' = it->>'iv') then
        raise exception 'Hóa đơn % đang có đề nghị thanh toán khác chờ duyệt.', iv->>'invNo'; end if;
      select * into pa from erp_partner where co = p_co and code = iv->>'vendor';
      if not pa.active or coalesce(pa.bank_acc,'') = '' then raise exception 'NCC % đang khóa hoặc chưa có tài khoản ngân hàng.', pa.code; end if;
      rem := (iv->>'total')::numeric - erp_iv_settled(p_co, it->>'iv') - coalesce((iv->>'dpAlloc')::numeric,0);
      amt := round(coalesce(erp_num(it,'amount'), rem));
      if amt <= 0 or amt > rem then raise exception 'Hóa đơn %: số tiền tối đa % đồng.', iv->>'invNo', erp_fm(rem); end if;
      items := items || jsonb_build_object('iv',it->>'iv','vendor',pa.code,'invSym',iv->>'invSym','invNo',iv->>'invNo','due',iv->>'due',
                                           'amount',amt,'bankAcc',pa.bank_acc,'bankName',pa.bank_name);
      tsum := tsum + amt;
    end loop;
    b := jsonb_build_object('date',to_char(d,'YYYY-MM-DD'),'dueBy',coalesce(b->>'dueBy',''),'items',items,'amount',tsum,'acc',erp_ad('BANK'),
                            'level', case when coalesce((cfg->>'poB')::numeric,0) > 0 and tsum > (cfg->>'poB')::numeric then 2 else 1 end,
                            'memo', coalesce(b->>'memo','Đợt thanh toán NCC'));
    st := 'pending'; pre := '160000';

  elsif p_type = 'PI' then   -- MI01 phiếu kiểm kê: chụp số sổ, đóng băng tồn
    if exists (select 1 from erp_doc where co = p_co and type = 'PI' and status in ('open','counted','pending')) then
      raise exception 'Đang có một phiếu kiểm kê chưa xử lý xong.'; end if;
    for m in select * from erp_mat mm where mm.co = p_co and mm.mtype <> 'DV' and mm.active
              and (coalesce(jsonb_typeof(b->'mats'),'') <> 'array' or jsonb_array_length(b->'mats') = 0 or b->'mats' ? mm.code) order by mm.code loop
      select qty, value into q, amt from erp_val where co = p_co and mat = m.code;
      items := items || jsonb_build_object('mat',m.code,'book',coalesce(q,0),'bookValue',coalesce(amt,0),'sloc',m.sloc);
    end loop;
    if jsonb_array_length(items) = 0 then raise exception 'Không có vật tư để kiểm kê.'; end if;
    b := jsonb_build_object('date',to_char(d,'YYYY-MM-DD'),'items',items,'members',coalesce(b->>'members',''),'memo',coalesce(b->>'memo','Kiểm kê định kỳ'));
    st := 'open'; pre := '700000';

  else
    raise exception 'Loại chứng từ % chưa hỗ trợ.', p_type;
  end if;

  select coalesce(max(seq),0) + 1 into s from erp_doc where co = p_co and type = p_type;
  v_id := p_type || lpad(s::text, 5, '0'); v_no := pre || lpad(s::text, 4, '0');
  if jsonb_array_length(je) > 0 then
    posted := erp_post(p_co, v_id, p_type, d, u.id, je, coalesce(b->>'reason', b->>'memo', ''));
    b := b || jsonb_build_object('je', posted->'lines', 'jeNo', posted->>'je', 'pdate', posted->>'date');
    if p_type = 'IV' then
      for it in select * from jsonb_array_elements(b->'items') loop
        diff := ((it->>'price')::numeric - (it->>'poPrice')::numeric) * (it->>'qty')::numeric + coalesce((it->>'frAlloc')::numeric,0);
        if diff <> 0 then perform erp_val_in(p_co, it->>'mat', 0, diff); end if;
      end loop;
    elsif p_type = 'CM' then
      for it in select * from jsonb_array_elements(b->'items') loop
        if (it->>'diff')::numeric <> 0 then perform erp_val_in(p_co, it->>'mat', 0, -(it->>'diff')::numeric); end if;
      end loop;
    end if;
  end if;
  b := b || jsonb_build_object('type',p_type,'seq',s,'no',v_no,'at',ts,'by',u.id::text,'role',r,'status',st,'date',coalesce(b->>'date',to_char(d,'YYYY-MM-DD')),
       'hist', jsonb_build_array(jsonb_build_object('at',ts,'by',u.id::text,'role',r,'act','create','note',note)));
  insert into erp_doc(co,id,type,seq,status,data) values (p_co, v_id, p_type, s, st, b);
  return jsonb_build_object('id', v_id, 'no', v_no, 'status', st, 'je', b->>'jeNo');
end $$;

-- ---------- Phê duyệt chứng từ P4 (gọi từ erp_doc_decide) ----------
create or replace function erp_mm_decide(p_token text, p_co text, p_id text, p_ok boolean, p_note text, p_act_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u erp_user; r text; d erp_doc; ns text; nd jsonb; ts text := erp_iso(); roles text[]; lines jsonb := '[]'; posted jsonb; it jsonb;
        cost numeric; costsum numeric := 0; m erp_mat; dq numeric; bal numeric; clr text; ins jsonb; pa erp_partner; pays jsonb := '[]';
        bankClear boolean; gd boolean; ktt boolean; shortv numeric := 0; overv numeric := 0; vv erp_val;
begin
  u := erp_auth(p_token);
  roles := case when u.is_admin then erp_act_roles(u, p_act_role) else erp_roles_of(u) end;
  if not u.is_admin and p_co is distinct from u.co then raise exception 'Không được phê duyệt chứng từ của công ty khác.'; end if;
  gd := 'GD' = any(roles) or (u.is_admin and coalesce(p_act_role,'') in ('GV','GD'));
  ktt := (not u.is_admin and erp_can_approve(u)) or (u.is_admin and coalesce(nullif(p_act_role,''),'GV') in ('GV','KTT'));
  perform pg_advisory_xact_lock(hashtext('erp:doc:' || p_co));
  select * into d from erp_doc where co = p_co and id = p_id for update;
  if not found then raise exception 'Không tìm thấy chứng từ.'; end if;
  if not ((d.status = 'pending' and d.type in ('PO','SCR','PI','PRUN')) or (d.status = 'pending2' and d.type in ('PO','PRUN'))) then
    raise exception 'Chứng từ không còn ở trạng thái chờ xử lý.'; end if;
  if d.status = 'pending2' then
    if not gd then raise exception 'Chứng từ vượt hạn mức B: cần Giám đốc duyệt cấp 2.'; end if;
    r := case when u.is_admin then coalesce(nullif(p_act_role,''),'GV') else 'GD' end;
    if not u.is_admin and d.data->>'decBy' = u.id::text then raise exception 'Vi phạm bất kiêm nhiệm: người duyệt cấp 1 không duyệt tiếp cấp 2.'; end if;
  else
    if not ktt then raise exception 'Chỉ Kế toán trưởng hoặc người được giao quyền phê duyệt mới được duyệt chứng từ.'; end if;
    r := case when u.is_admin then coalesce(nullif(p_act_role,''),'GV') when erp_can(erp_roles_of(u),'SBWP','A') then 'KTT' else 'T:AP' end;
  end if;
  if d.data->>'by' = u.id::text and not u.is_admin then raise exception 'Vi phạm bất kiêm nhiệm: không được phê duyệt chứng từ do chính mình lập.'; end if;
  if d.data->>'by' = u.id::text and p_ok and coalesce(trim(p_note),'') = '' then
    raise exception 'Tự duyệt chứng từ do chính mình lập phải ghi lý do (ngoại lệ kiêm nhiệm).'; end if;
  if not p_ok and coalesce(trim(p_note),'') = '' then raise exception 'Hãy ghi lý do từ chối.'; end if;
  nd := d.data;
  bankClear := coalesce((select (v->>'bankClear')::boolean from erp_cfg where k = 'main'), true);

  if not p_ok then
    ns := 'rejected';
  elsif d.type = 'PO' then
    ns := case when d.status = 'pending' and coalesce((d.data->>'level')::int,1) = 2 then 'pending2' else 'approved' end;
  elsif d.type = 'SCR' then   -- 551 hủy hàng hỏng: Nợ 632 / Có 156 theo giá bình quân
    for it in select * from jsonb_array_elements(d.data->'items') loop
      select * into m from erp_mat where co = p_co and code = it->>'mat';
      cost := erp_val_out(p_co, m.code, (it->>'qty')::numeric); costsum := costsum + cost;
      lines := lines || jsonb_build_object('a',m.acc,'cr',cost,'mat',m.code,'q',(it->>'qty')::numeric);
    end loop;
    lines := jsonb_build_array(jsonb_build_object('a',erp_ad('SCRAP'),'dr',costsum)) || lines;
    posted := erp_post(p_co, d.id, 'SCR', null, u.id, lines, 'Hủy hàng hỏng: ' || coalesce(d.data->>'reason',''));
    nd := nd || jsonb_build_object('je',posted->'lines','jeNo',posted->>'je','pdate',posted->>'date','value',costsum);
    ns := 'posted';
  elsif d.type = 'PI' then   -- MI07 ghi sổ chênh lệch kiểm kê theo giá bình quân hiện hành
    perform set_config('erp.pi_post','on',true);
    for it in select * from jsonb_array_elements(d.data->'items') loop
      dq := coalesce((it->>'diff')::numeric,0); if dq = 0 then continue; end if;
      select * into m from erp_mat where co = p_co and code = it->>'mat';
      select * into vv from erp_val where co = p_co and mat = m.code;
      if coalesce(vv.qty,0) <> (it->>'book')::numeric then raise exception 'Sổ kho % đã thay đổi từ lúc lập phiếu kiểm kê.', m.code; end if;
      if dq < 0 then
        cost := erp_val_out(p_co, m.code, -dq); shortv := shortv + cost;
        lines := lines || jsonb_build_object('a',m.acc,'cr',cost,'mat',m.code,'q',-dq);
      else
        cost := case when coalesce(vv.qty,0) > 0 then round(vv.value / vv.qty * dq) else round(m.buy_price * dq) end; overv := overv + cost;
        perform erp_val_in(p_co, m.code, dq, cost);
        lines := lines || jsonb_build_object('a',m.acc,'dr',cost,'mat',m.code,'q',dq);
      end if;
    end loop;
    perform set_config('erp.pi_post','',true);
    if shortv > 0 then lines := jsonb_build_array(jsonb_build_object('a',erp_ad('INV_SHORT'),'dr',shortv)) || lines; end if;
    if overv > 0 then lines := lines || jsonb_build_object('a',erp_ad('INV_OVER'),'cr',overv); end if;
    if jsonb_array_length(lines) > 0 then
      posted := erp_post(p_co, d.id, 'PI', null, u.id, lines, 'Chênh lệch kiểm kê kho');
      nd := nd || jsonb_build_object('je',posted->'lines','jeNo',posted->>'je','pdate',posted->>'date');
    end if;
    nd := nd || jsonb_build_object('short',shortv,'over',overv);
    ns := 'posted';
  elsif d.type = 'PRUN' then
    if d.status = 'pending' and coalesce((d.data->>'level')::int,1) = 2 then ns := 'pending2';
    else
      -- Duyệt xong: lập phiếu chi chuyển khoản cho từng hóa đơn (Nợ 331 / Có 113 hoặc 112)
      clr := case when bankClear then erp_ad('BANK_CLR') else erp_ad('BANK') end;
      bal := erp_balance(p_co, erp_ad('BANK')) + case when bankClear then least(erp_balance(p_co, erp_ad('BANK_CLR')),0) else 0 end;
      if bal < (d.data->>'amount')::numeric then raise exception 'Không đủ số dư tiền gửi khả dụng (% đồng) cho đợt thanh toán.', erp_fm(bal); end if;
      for it in select * from jsonb_array_elements(d.data->'items') loop
        select * into pa from erp_partner where co = p_co and code = it->>'vendor';
        if not found or not pa.active then raise exception 'NCC % đang bị khóa: loại hóa đơn % khỏi đợt rồi lập lại.', it->>'vendor', it->>'invNo'; end if;
        if (select (data->>'total')::numeric - coalesce((data->>'dpAlloc')::numeric,0) from erp_doc where co = p_co and id = it->>'iv')
           - erp_iv_settled(p_co, it->>'iv') < (it->>'amount')::numeric then
          raise exception 'Hóa đơn % đã được thanh toán một phần trong lúc chờ duyệt đợt.', it->>'invNo'; end if;
        ins := erp_doc_ins(p_co, 'PAY', 'posted', jsonb_build_object('iv',it->>'iv','vendor',pa.code,'acc',erp_ad('BANK'),'amount',(it->>'amount')::numeric,
                 'settle',(it->>'amount')::numeric,'disc',0,'date',to_char(erp_wdate(p_co),'YYYY-MM-DD'),'run',d.id,'runNo',d.data->>'no',
                 'bankAcc',pa.bank_acc,'bankName',pa.bank_name,'memo','Thanh toán hóa đơn ' || (it->>'invSym') || ' số ' || (it->>'invNo') || ' (đợt ' || (d.data->>'no') || ')',
                 'at',ts,'by',d.data->>'by','role','AP','decBy',u.id::text,'decAt',ts,
                 'hist',jsonb_build_array(jsonb_build_object('at',ts,'by',u.id::text,'role',r,'act','create','note','Sinh từ đợt thanh toán ' || (d.data->>'no')))));
        posted := erp_post(p_co, ins->>'id', 'PAY', null, u.id,
          jsonb_build_array(jsonb_build_object('a',erp_ad('AP'),'dr',(it->>'amount')::numeric,'p',pa.code), jsonb_build_object('a',clr,'cr',(it->>'amount')::numeric)),
          'Đợt thanh toán ' || (d.data->>'no'));
        update erp_doc set data = data || jsonb_build_object('je',posted->'lines','jeNo',posted->>'je','pdate',posted->>'date')
                                       || case when bankClear then jsonb_build_object('clr', clr) else '{}'::jsonb end
         where co = p_co and id = ins->>'id';
        pays := pays || jsonb_build_object('pay', ins->>'id', 'no', ins->>'no', 'iv', it->>'iv');
      end loop;
      nd := nd || jsonb_build_object('pays', pays);
      ns := 'posted';
    end if;
  end if;

  nd := nd || jsonb_build_object('status', ns,
        'decBy', case when d.status = 'pending' then u.id::text else nd->>'decBy' end,
        'decAt', case when d.status = 'pending' then ts else nd->>'decAt' end,
        'dec2By', case when d.status = 'pending2' then u.id::text else nd->>'dec2By' end,
        'hist', coalesce(nd->'hist','[]'::jsonb) || jsonb_build_array(jsonb_build_object('at',ts,'by',u.id::text,'role',r,
                 'act', case when not p_ok then 'reject' when ns = 'pending2' then 'approve1' else 'approve' end, 'note', coalesce(p_note,''),
                 'self', d.data->>'by' = u.id::text)));
  update erp_doc set status = ns, data = nd, updated_at = clock_timestamp() where co = p_co and id = p_id;
  return jsonb_build_object('status', ns);
end $$;

-- ---------- MI04: giảng viên nhập số kiểm đếm thực tế; MI07: Thủ kho trình ghi sổ chênh lệch ----------
create or replace function erp_pi_count(p_token text, p_co text, p_id text, p_counts jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u erp_user; d erp_doc; items jsonb := '[]'; it jsonb; c numeric;
begin
  u := erp_auth(p_token);
  if not u.is_admin then raise exception 'Chỉ giảng viên nhập số kiểm đếm thực tế (mô phỏng kết quả đếm của tổ kiểm kê).'; end if;
  perform pg_advisory_xact_lock(hashtext('erp:doc:' || p_co));
  select * into d from erp_doc where co = p_co and id = p_id for update;
  if not found or d.type <> 'PI' or d.status not in ('open','counted') then raise exception 'Phiếu kiểm kê không ở trạng thái nhập số đếm.'; end if;
  for it in select * from jsonb_array_elements(d.data->'items') loop
    c := coalesce(erp_num(p_counts, it->>'mat'), (it->>'book')::numeric);
    if c < 0 or c <> trunc(c) then raise exception 'Số đếm của % phải là số nguyên không âm.', it->>'mat'; end if;
    items := items || (it || jsonb_build_object('counted', c, 'diff', c - (it->>'book')::numeric));
  end loop;
  update erp_doc set status = 'counted', updated_at = clock_timestamp(),
    data = data || jsonb_build_object('items', items, 'status', 'counted', 'countAt', erp_iso(),
      'hist', coalesce(data->'hist','[]'::jsonb) || jsonb_build_array(jsonb_build_object('at',erp_iso(),'by',u.id::text,'role','GV','act','count','note','Nhập số kiểm đếm')))
   where co = p_co and id = p_id;
  return jsonb_build_object('status','counted');
end $$;
create or replace function erp_pi_submit(p_token text, p_co text, p_id text, p_note text, p_act_role text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u erp_user; d erp_doc; r text; ts text := erp_iso();
begin
  u := erp_auth(p_token);
  if not u.is_admin and p_co is distinct from u.co then raise exception 'Không được xử lý chứng từ của công ty khác.'; end if;
  if not erp_can(erp_act_roles(u, p_act_role), 'MI07', 'C') then raise exception 'Vai trò của bạn không được trình ghi sổ kiểm kê (MI07).'; end if;
  r := case when u.is_admin then coalesce(nullif(p_act_role,''),'GV') else 'KHO' end;
  perform pg_advisory_xact_lock(hashtext('erp:doc:' || p_co));
  select * into d from erp_doc where co = p_co and id = p_id for update;
  if not found or d.type <> 'PI' or d.status <> 'counted' then raise exception 'Phiếu kiểm kê chưa có số đếm (MI04).'; end if;
  if exists (select 1 from jsonb_array_elements(d.data->'items') it where (it->>'diff')::numeric <> 0) and coalesce(trim(p_note),'') = '' then
    raise exception 'Có chênh lệch: ghi nguyên nhân sơ bộ (hao hụt, nhầm lẫn khi nhập xuất…) trước khi trình duyệt.'; end if;
  update erp_doc set status = 'pending', updated_at = clock_timestamp(),
    data = data || jsonb_build_object('status','pending','reason',coalesce(p_note,''),
      'hist', coalesce(data->'hist','[]'::jsonb) || jsonb_build_array(jsonb_build_object('at',ts,'by',u.id::text,'role',r,'act','submit','note',coalesce(p_note,''))))
   where co = p_co and id = p_id;
  return jsonb_build_object('status','pending');
end $$;

-- ---------- Nối vào erp_doc_create, erp_doc_decide ----------
do $do$ declare d text; begin
  select pg_get_functiondef('erp_doc_create(text,text,text,jsonb,text,text)'::regprocedure) into d;
  if position('erp_mm_create(' in d) = 0 then
    if position($o$  if p_type not in ('PR','PO','GR','IV','PAY','SO','DL','BI','RC','JE','CJ','CNT','ADV','ADS') then raise exception 'Loại chứng từ % không tồn tại.', p_type; end if;$o$ in d) = 0 then
      raise exception 'erp_doc_create: không tìm thấy danh sách loại chứng từ'; end if;
    d := replace(d, $o$  if p_type not in ('PR','PO','GR','IV','PAY','SO','DL','BI','RC','JE','CJ','CNT','ADV','ADS') then raise exception 'Loại chứng từ % không tồn tại.', p_type; end if;$o$,
                    $n$  if p_type not in ('PR','PO','GR','IV','PAY','SO','DL','BI','RC','JE','CJ','CNT','ADV','ADS','RFQ','QT','RTV','TRF','GI','SCR','CM','PRUN','PI') then raise exception 'Loại chứng từ % không tồn tại.', p_type; end if;$n$);
    if position($o$  perform pg_advisory_xact_lock(hashtext('erp:doc:' || p_co));

  if p_type in ('PR','SO') then$o$ in d) = 0 then raise exception 'erp_doc_create: không tìm thấy điểm nối'; end if;
    d := replace(d, $o$  perform pg_advisory_xact_lock(hashtext('erp:doc:' || p_co));

  if p_type in ('PR','SO') then$o$, $n$  perform pg_advisory_xact_lock(hashtext('erp:doc:' || p_co));

  -- P4: mua hàng, kho nâng cao, thanh toán NCC xử lý ở erp_mm_create (006_mm.sql)
  if p_type in ('PO','IV','PAY','RFQ','QT','RTV','TRF','GI','SCR','CM','PRUN','PI') then
    return erp_mm_create(u, r, v_roles, p_co, p_type, b || jsonb_strip_nulls(jsonb_build_object('invNo', p_body->'invNo')), p_note, d);
  end if;

  if p_type in ('PR','SO') then$n$);
    -- MIGO 101: dung sai số lượng nhận và nhận thuần (trừ hàng đã trả 122)
    if position($o$      rem := erp_num(src->'items'->i,'qty') - erp_kid_qty(p_co,'GR','po',b->>'po',i);
      if q > rem then raise exception 'Nhập vượt đơn mua: % chỉ còn % cần nhận. Hàng giao thừa phải lập biên bản và trả lại NCC.', src->'items'->i->>'mat', rem; end if;$o$ in d) = 0 then
      raise exception 'erp_doc_create: không tìm thấy kiểm tra nhập vượt'; end if;
    d := replace(d, $o$      rem := erp_num(src->'items'->i,'qty') - erp_kid_qty(p_co,'GR','po',b->>'po',i);
      if q > rem then raise exception 'Nhập vượt đơn mua: % chỉ còn % cần nhận. Hàng giao thừa phải lập biên bản và trả lại NCC.', src->'items'->i->>'mat', rem; end if;$o$,
                    $n$      rem := erp_num(src->'items'->i,'qty') - erp_po_recv(p_co, b->>'po', i);
      if q > rem + floor(erp_num(src->'items'->i,'qty') * coalesce((cfg->>'grTol')::numeric,0) / 100) then
        raise exception 'Nhập vượt đơn mua: % còn % cần nhận (dung sai % %%). Hàng giao thừa phải lập biên bản và trả lại NCC.', src->'items'->i->>'mat', rem, coalesce((cfg->>'grTol')::numeric,0); end if;$n$);
    execute d;
  end if;
end $do$;

do $do$ declare d text; begin
  select pg_get_functiondef('erp_doc_decide(text,text,text,boolean,text,text)'::regprocedure) into d;
  if position('erp_mm_decide(' in d) = 0 then
    if position($o$begin
  u := erp_auth(p_token);
  if u.is_admin then$o$ in d) = 0 then raise exception 'erp_doc_decide: không tìm thấy điểm nối'; end if;
    d := replace(d, $o$begin
  u := erp_auth(p_token);
  if u.is_admin then$o$, $n$begin
  -- P4: đơn mua (duyệt 2 cấp), hủy hàng, kiểm kê, đợt thanh toán xử lý ở erp_mm_decide (006_mm.sql)
  if exists (select 1 from erp_doc where co = p_co and id = p_id and type in ('PO','SCR','PI','PRUN')) then
    return erp_mm_decide(p_token, p_co, p_id, p_ok, p_note, p_act_role);
  end if;
  u := erp_auth(p_token);
  if u.is_admin then$n$);
    execute d;
  end if;
end $do$;

-- ---------- Chiết khấu thanh toán: ghi Có 515 khi chi; kiểm tra còn trong hạn lúc chi ----------
do $do$ declare d text; begin
  select pg_get_functiondef('erp_doc_decide(text,text,text,boolean,text,text)'::regprocedure) into d;
  if position('PAY_DISC' in d) = 0 then
    d := replace(d, $o$      posted := erp_post(p_co, d.id, 'PAY', null, u.id,
        jsonb_build_array(jsonb_build_object('a',erp_ad('AP'),'dr',amt,'p',d.data->>'vendor'), jsonb_build_object('a',clr,'cr',amt)), '');$o$,
      $n$      if coalesce((d.data->>'disc')::numeric,0) > 0 and wd > (d.data->>'discUntil')::date then
        raise exception 'Đã quá hạn hưởng chiết khấu thanh toán (%): từ chối đề nghị này và lập lại không chiết khấu.', to_char((d.data->>'discUntil')::date,'DD/MM/YYYY'); end if;
      posted := erp_post(p_co, d.id, 'PAY', null, u.id,
        jsonb_build_array(jsonb_build_object('a',erp_ad('AP'),'dr',amt + coalesce((d.data->>'disc')::numeric,0),'p',d.data->>'vendor'), jsonb_build_object('a',clr,'cr',amt))
        || case when coalesce((d.data->>'disc')::numeric,0) > 0 then jsonb_build_array(jsonb_build_object('a',erp_ad('PAY_DISC'),'cr',(d.data->>'disc')::numeric)) else '[]'::jsonb end,
        coalesce(d.data->>'memo',''));$n$);
    if position('PAY_DISC' in d) = 0 then raise exception 'erp_doc_decide: không tìm thấy bút toán chi chuyển khoản'; end if;
    execute d;
  end if;
  select pg_get_functiondef('erp_cash_confirm(text,text,text,text)'::regprocedure) into d;
  if position('PAY_DISC' in d) = 0 then
    d := replace(d, $o$    lines := jsonb_build_array(jsonb_build_object('a',erp_ad('AP'),'dr',amt,'p',d.data->>'vendor'), jsonb_build_object('a',erp_ad('CASH'),'cr',amt));$o$,
      $n$    if coalesce((d.data->>'disc')::numeric,0) > 0 and erp_wdate(p_co) > (d.data->>'discUntil')::date then
      raise exception 'Đã quá hạn hưởng chiết khấu thanh toán: trả lại chứng từ để lập lại không chiết khấu.'; end if;
    lines := jsonb_build_array(jsonb_build_object('a',erp_ad('AP'),'dr',amt + coalesce((d.data->>'disc')::numeric,0),'p',d.data->>'vendor'), jsonb_build_object('a',erp_ad('CASH'),'cr',amt))
      || case when coalesce((d.data->>'disc')::numeric,0) > 0 then jsonb_build_array(jsonb_build_object('a',erp_ad('PAY_DISC'),'cr',(d.data->>'disc')::numeric)) else '[]'::jsonb end;$n$);
    if position('PAY_DISC' in d) = 0 then raise exception 'erp_cash_confirm: không tìm thấy bút toán chi tiền mặt'; end if;
    execute d;
  end if;
  -- Dữ liệu gốc gửi trình duyệt: thêm điều khoản chiết khấu
  select pg_get_functiondef('erp_md_json(text)'::regprocedure) into d;
  if position('disc_pct' in d) = 0 then
    d := replace(d, $o$'addr',address,'bank',bank_acc,'bankName',bank_name,'active',active,'ok',confirmed)$o$,
                    $n$'addr',address,'bank',bank_acc,'bankName',bank_name,'active',active,'ok',confirmed,'disc',disc_pct,'discDays',disc_days)$n$);
    if position('disc_pct' in d) = 0 then raise exception 'erp_md_json: không tìm thấy danh sách đối tác'; end if;
    execute d;
  end if;
end $do$;

-- ---------- Phân quyền hàm ----------
do $$
declare f text;
begin
  foreach f in array array['erp_mm_create(erp_user,text,text[],text,text,jsonb,text,date)','erp_mm_decide(text,text,text,boolean,text,text)',
    'erp_pi_frozen(text,text)','erp_sloc_qty(text,text,text)','erp_po_recv(text,text,integer)','erp_iv_settled(text,text)',
    'erp_dp_open(text,text)','erp_po_level(numeric)','erp_tax_ok(numeric)','erp_val_in(text,text,numeric,numeric)','erp_val_out(text,text,numeric)'] loop
    execute 'revoke execute on function ' || f || ' from public';
    if exists (select 1 from pg_roles where rolname='anon') then execute 'revoke execute on function ' || f || ' from anon'; end if;
    if exists (select 1 from pg_roles where rolname='authenticated') then execute 'revoke execute on function ' || f || ' from authenticated'; end if;
  end loop;
  foreach f in array array['erp_pi_count(text,text,text,jsonb)','erp_pi_submit(text,text,text,text,text)'] loop
    execute 'revoke execute on function ' || f || ' from public';
    if exists (select 1 from pg_roles where rolname='anon') then execute 'grant execute on function ' || f || ' to anon'; end if;
    if exists (select 1 from pg_roles where rolname='authenticated') then execute 'grant execute on function ' || f || ' to authenticated'; end if;
  end loop;
end $$;
