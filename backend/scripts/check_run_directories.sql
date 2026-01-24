-- Check what's stored in zoho_project_run_directories table
-- This helps verify the data structure and see if queries will match

SELECT 
    id,
    zoho_project_id,
    zoho_project_name,
    user_id,
    user_name,
    block_name,
    experiment_name,
    run_directory,
    created_at,
    updated_at
FROM zoho_project_run_directories
ORDER BY updated_at DESC
LIMIT 20;

-- Check for specific project "ganga"
SELECT 
    id,
    zoho_project_id,
    zoho_project_name,
    user_id,
    user_name,
    block_name,
    experiment_name,
    run_directory,
    created_at,
    updated_at
FROM zoho_project_run_directories
WHERE LOWER(zoho_project_name) = LOWER('ganga')
   OR zoho_project_id = '173458000001945100'
ORDER BY updated_at DESC;

-- Check what user_ids and user_names are stored
SELECT DISTINCT 
    user_id,
    user_name,
    COUNT(*) as count
FROM zoho_project_run_directories
GROUP BY user_id, user_name
ORDER BY count DESC;

