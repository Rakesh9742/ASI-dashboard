-- RTL tags created by engineers during experiment setup, linked to user and block.
-- Engineer can create multiple RTL tags per block and reuse them for new experiments.
CREATE TABLE IF NOT EXISTS user_block_rtl_tags (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    block_id INT NOT NULL REFERENCES blocks(id) ON DELETE CASCADE,
    rtl_tag VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (user_id, block_id, rtl_tag)
);

CREATE INDEX IF NOT EXISTS idx_user_block_rtl_tags_user_block ON user_block_rtl_tags(user_id, block_id);
COMMENT ON TABLE user_block_rtl_tags IS 'RTL tags created by engineers for a block during experiment setup; used for dropdown and linking runs to creator.';
