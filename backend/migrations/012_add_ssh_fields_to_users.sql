-- Add SSH connection fields to users table
-- These fields are for SSH access configuration (admin only can set these)

ALTER TABLE users 
ADD COLUMN IF NOT EXISTS ipaddress VARCHAR(255),
ADD COLUMN IF NOT EXISTS port INTEGER,
ADD COLUMN IF NOT EXISTS ssh_user VARCHAR(255),
ADD COLUMN IF NOT EXISTS sshpassword_hash VARCHAR(255);

-- Add index for ipaddress if needed for queries
CREATE INDEX IF NOT EXISTS idx_users_ipaddress ON users(ipaddress) WHERE ipaddress IS NOT NULL;

-- Add comment to document these fields
COMMENT ON COLUMN users.ipaddress IS 'SSH server IP address (admin only)';
COMMENT ON COLUMN users.port IS 'SSH server port (admin only)';
COMMENT ON COLUMN users.ssh_user IS 'SSH username (admin only)';
COMMENT ON COLUMN users.sshpassword_hash IS 'Hashed SSH password (admin only)';

