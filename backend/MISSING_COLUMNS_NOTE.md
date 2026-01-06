# Missing Columns in c_report_data Table

## Status
The following columns are currently commented out in the code because they don't exist in the database table yet. The code will use `NULL` values for these columns until the migration is run.

## Columns to Add (via migration 013_add_check_item_details.sql)

The following columns need to be added to the `c_report_data` table:

1. **description** - TEXT
   - Description of the report data

2. **fix_details** - TEXT
   - Details about fixes applied

3. **engineer_comments** - TEXT
   - Comments from the engineer

4. **lead_comments** - TEXT
   - Comments from the lead

5. **result_value** - TEXT
   - Result or value from the check

6. **signoff_status** - VARCHAR(50)
   - Status of the signoff (e.g., 'pending', 'approved', 'rejected')

7. **signoff_by** - INT REFERENCES users(id) ON DELETE SET NULL
   - User ID who signed off on the report

8. **signoff_at** - TIMESTAMP
   - Timestamp when the signoff occurred

## Migration File
These columns are defined in: `migrations/013_add_check_item_details.sql`

## To Apply
Run the migration:
```bash
cd backend
npm run migrate up
```

Or manually run the SQL from `migrations/013_add_check_item_details.sql`

## Current Behavior
- The code checks for column existence before using them
- If columns don't exist, `NULL` values are returned
- The application will work but these fields will be empty/null
- Once the migration is run, the columns will be automatically used

