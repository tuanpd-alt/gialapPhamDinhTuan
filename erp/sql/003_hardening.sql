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
