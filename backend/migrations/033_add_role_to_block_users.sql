-- Add task-level role to block_users (block = Zoho task).
-- Set only when admin does Sync Projects: we read task.owner_role from Zoho and map to our role.
-- Same role values as user_projects: admin, project_manager, lead, engineer, customer.
-- No default: if Zoho does not provide role, we store NULL and record an error.
ALTER TABLE block_users
  ADD COLUMN IF NOT EXISTS role VARCHAR(50);

COMMENT ON COLUMN block_users.role IS 'Task-level role for this block assignment (from Zoho task owner_role). E.g. user is engineer in project but Lead for this block/task.';

CREATE INDEX IF NOT EXISTS idx_block_users_role ON block_users(role);
