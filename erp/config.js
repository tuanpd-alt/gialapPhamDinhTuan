// Cấu hình kết nối Supabase cho ERP Lab.
// NHÁNH erp2 = MÔI TRƯỜNG THỬ (project erp-lab-dev). Khi phát hành (P13) đổi lại về project erp-lab của lớp.
// "anon public key" là khóa công khai, được phép để trong mã nguồn; KHÔNG dán "service_role key" vào đây.
window.ERP_CONFIG = {
  env: "dev",
  supabaseUrl: "https://vanyydjtvcbejpyofeua.supabase.co",
  supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZhbnl5ZGp0dmNiZWpweW9mZXVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQzODA3MjIsImV4cCI6MjEwOTk1NjcyMn0.mK0LMxLD4GNmiW10sEZtCDorv3M8ORvIIQgJT8CPP8I"
};
