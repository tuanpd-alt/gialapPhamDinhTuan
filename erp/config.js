// Cấu hình kết nối Supabase cho ERP Lab.
// Lấy 2 giá trị này ở Supabase > Project Settings > API (hoặc nút "Connect").
// "anon public key" là khóa công khai, được phép để trong mã nguồn; KHÔNG dán "service_role key" vào đây.
window.ERP_CONFIG = {
  supabaseUrl: "DIEN_PROJECT_URL",        // ví dụ: https://abcdxyz.supabase.co
  supabaseAnonKey: "DIEN_ANON_PUBLIC_KEY" // chuỗi dài bắt đầu bằng eyJ... hoặc sb_publishable_...
};
