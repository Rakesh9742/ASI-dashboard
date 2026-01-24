-- Script to delete data from projects and zoho_projects_mapping tables
-- WARNING: This will delete ALL data from these tables
-- Related data in other tables will be handled by foreign key constraints:
--   - project_domains: CASCADE delete
--   - user_projects: CASCADE delete
--   - blocks: CASCADE delete
--   - zoho_projects_mapping.local_project_id: SET NULL

-- Step 1: Delete all data from zoho_projects_mapping
DELETE FROM zoho_projects_mapping;

-- Step 2: Delete all data from projects
-- This will cascade delete related records in:
--   - project_domains
--   - user_projects
--   - blocks (and related tables)
DELETE FROM projects;

-- Verify deletions
SELECT 'zoho_projects_mapping' as table_name, COUNT(*) as remaining_rows FROM zoho_projects_mapping
UNION ALL
SELECT 'projects' as table_name, COUNT(*) as remaining_rows FROM projects;

