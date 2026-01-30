-- Add check_name column and remove auto_approve from check_items

ALTER TABLE check_items
ADD COLUMN IF NOT EXISTS check_name VARCHAR(255);

COMMENT ON COLUMN check_items.check_name IS 'Optional user-facing name for the check item (not used yet)';

ALTER TABLE check_items
DROP COLUMN IF EXISTS auto_approve;

