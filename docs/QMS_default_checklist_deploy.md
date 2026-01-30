# QMS Default Checklist Deployment (Auto Removal + check_name + Backfill + External JSON)

This document captures the changes and the steps needed to deploy them to staging.

## What Changed
- **Removed Auto field**: `auto_approve` column removed from `check_items` table and from UI (QMS checklist table + history dialog).
- **Added check_name**: new nullable column `check_name` in `check_items` (kept empty unless provided by JSON report).
- **Default checklist creation**:
  - For **existing** block + experiment pairs, backfill creates one checklist using the default template.
  - For **new** experiments created via setup (`/api/projects/save-run-directory`), a default checklist is created automatically.
- **Templates**:
  - Default checklist template: `Synthesis_QMS.xlsx` (under `backend/templates/`)
  - External JSON report: `syn_qms.json` (under `backend/templates/`)
- **External JSON QMS upload**:
  - New endpoint: `/api/qms/external-checklists/upload-report`
  - Uses JSON report to update only matching Check IDs
  - Resets checklist to `draft` to force resubmission

## Files Updated (Reference)
- Backend
  - `backend/src/services/qms.service.ts`
  - `backend/src/routes/qms.routes.ts`
  - `backend/src/routes/project.routes.ts`
  - `backend/templates/Synthesis_QMS.xlsx`
  - `backend/templates/syn_qms.json`
- Frontend
  - `frontend/lib/screens/qms_checklist_detail_screen.dart`
  - `frontend/lib/widgets/qms_history_dialog.dart`
  - `frontend/lib/widgets/qms_status_badge.dart`
- Migrations
  - `backend/migrations/031_add_check_name_remove_auto.sql`
  - `backend/migrations/combined_qms_and_roles_migration.sql`
  - `backend/migrations/complete_schema.sql`
  - `backend/migrations/012_create_qms_schema.sql`
  - `backend/migrations/015_ensure_qms_columns_exist.sql`

## Staging Deployment Steps

### 1) Ensure Templates Exist on Staging
Copy both templates to the backend templates folder (inside the backend container or the mounted volume):
```bash
cp Synthesis_QMS.xlsx backend/templates/Synthesis_QMS.xlsx
cp backend/templates/syn_qms.json backend/templates/syn_qms.json
```

If you have the repo on staging:
```bash
cp Synthesis_QMS.xlsx backend/templates/Synthesis_QMS.xlsx
```

If backend runs in Docker with a bind mount, make sure the files exist on the host and are visible in the container at:
```
/app/templates/Synthesis_QMS.xlsx
/app/templates/syn_qms.json
```

### 2) Run Migration (check_name + drop auto_approve)
Run the migration on staging DB:
```bash
psql -U postgres -d ASI -f backend/migrations/031_add_check_name_remove_auto.sql
```

If using Docker:
```bash
docker exec -i asi_postgres psql -U postgres -d ASI < backend/migrations/031_add_check_name_remove_auto.sql
```

### 3) Rebuild + Restart Backend
Because QMS parsing & checklist creation logic changed, rebuild the backend and restart:
```bash
# If using docker-compose
docker-compose build backend
docker-compose up -d backend
```

If backend is already running with a bind mount and TS build output is stale:
```bash
docker exec -i asi_backend npm run build
docker restart asi_backend
```

### 4) Rebuild + Restart Frontend
Frontend shows the Check Name column and updated status badges:
```bash
docker-compose build frontend
docker-compose up -d frontend
```

### 5) Backfill Default Checklists (Existing Data)
Run backfill to create a default checklist for **all existing** block+experiment pairs:
```bash
curl -X POST http://<backend-host>/api/qms/checklists/backfill-default-template \
  -H "Authorization: Bearer <ADMIN_TOKEN>"
```

Expected response:
```json
{
  "success": true,
  "message": "Default checklists backfilled",
  "totalPairs": <n>,
  "processed": <n>
}
```

### 6) Verify New Experiments Auto‑Create Checklists
Create a new experiment (setup flow), then check QMS checklist list:
```bash
GET /api/qms/blocks/<blockId>/checklists
```
You should see one checklist named:
```
Synthesis QMS - <experimentName>
```

## External JSON QMS Upload (Staging)
New endpoint (no checklist id in URL):
```bash
curl -X POST "http://<backend-host>/api/qms/external-checklists/upload-report" \
  -H "X-API-Key: <API_KEY>" \
  -H "Content-Type: application/json" \
  -d "{\"report_path\":\"/app/templates/syn_qms.json\"}"
```

Behavior:
- Uses JSON fields `project`, `block_name`, and experiment (from `stage_directory` segment after block name).
- Updates only matching Check IDs.
- Updates `check_name` only if present in JSON.
- Returns `missing_check_ids` and `extra_check_ids`.
- Resets checklist to `draft` (forces engineer resubmission).

## Notes / Behavior
- `check_name` is **nullable** and only populated by JSON report.
- The Excel parser ignores the `Auto` column (removed from template).
- Checklist auto‑creation is triggered only when a **new** run is created in `/api/projects/save-run-directory`.
- Backfill can be run multiple times safely; it uses existing checklist names per block.


```
curl -X POST "http://localhost:3000/api/qms/external-checklists/upload-report" \
  -H "X-API-Key: sitedafilesdata" \
  -H "Content-Type: application/json" \
  -d "{\"report_path\":\"/app/templates/syn_qms.json\"}"
```