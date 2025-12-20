-- Add admin user with username admin1, email admin@1.com and password test@1234
-- Password hash for 'test@1234' using bcrypt with salt rounds 10
INSERT INTO users (username, email, password_hash, full_name, role, is_active) VALUES
('admin1', 'admin@1.com', '$2a$10$6fuNS9.c5gNt20SsPmmTPO04289kKQcI1wr1QFiCcMt7McQTZSsQC', 'Admin User', 'admin', true)
ON CONFLICT (username) DO UPDATE SET
  email = EXCLUDED.email,
  password_hash = EXCLUDED.password_hash,
  role = EXCLUDED.role,
  is_active = EXCLUDED.is_active;

-- Also allow login with email as username
-- Note: The login endpoint accepts both username and email

