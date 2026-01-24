-- Update admin1 user password hash
UPDATE users 
SET password_hash = '$2a$10$6fuNS9.c5gNt20SsPmmTPO04289kKQcI1wr1QFiCcMt7McQTZSsQC' 
WHERE username = 'admin1';

-- Verify the update
SELECT username, email, LEFT(password_hash, 30) as hash_preview 
FROM users 
WHERE username = 'admin1';





























