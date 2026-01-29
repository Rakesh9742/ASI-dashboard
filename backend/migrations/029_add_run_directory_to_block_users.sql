-- Add run_directory to block_users so each block-user pair stores its run directory
-- (set when engineer completes setup; run directory varies per block)
ALTER TABLE block_users
  ADD COLUMN IF NOT EXISTS run_directory TEXT;

COMMENT ON COLUMN block_users.run_directory IS 'Run directory path for this block/user (set when engineer completes setup)';
