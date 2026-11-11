#!/bin/sh
# Gộp erp/sql/*.sql thành erp/setup.sql để giảng viên chỉ chạy một tệp trong SQL Editor.
# Chạy từ thư mục gốc kho:  sh erp/tools/build-setup.sh
set -e
cd "$(dirname "$0")/.."
{
  echo "-- ====================================================================="
  echo "-- ERP Lab – cài đặt/cập nhật cơ sở dữ liệu trên Supabase (TỆP SINH TỰ ĐỘNG từ erp/sql/*.sql)"
  echo "-- Cách dùng: Supabase > SQL Editor > New query > dán toàn bộ > Run. Chạy lại an toàn, không xóa dữ liệu."
  echo "-- TRƯỚC KHI CHẠY: sửa mật khẩu giảng viên ở dòng cuối cùng."
  echo "-- ====================================================================="
  for f in sql/[0-9][0-9][0-9]_*.sql; do
    echo; echo "-- >>>>>>>>>> $f"; cat "$f"
  done
  echo
  echo "-- ---------- Tài khoản giảng viên: SỬA MẬT KHẨU TRƯỚC KHI CHẠY ----------"
  echo "select erp_create_admin('gv', 'DoiMatKhauNay@2026', 'Giảng viên');"
} > setup.sql
echo "Đã tạo erp/setup.sql ($(wc -l < setup.sql) dòng)"
