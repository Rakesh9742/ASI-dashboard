-- Block-to-user assignment: which users are assigned to which block (from Zoho task owners).
-- Synced when admin does Sync Projects; used so engineers see only blocks assigned to them.
CREATE TABLE IF NOT EXISTS block_users (
    block_id INTEGER NOT NULL REFERENCES blocks(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (block_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_block_users_block_id ON block_users(block_id);
CREATE INDEX IF NOT EXISTS idx_block_users_user_id ON block_users(user_id);

COMMENT ON TABLE block_users IS 'Maps blocks to assigned users (from Zoho task owners). Synced on Sync Projects.';
