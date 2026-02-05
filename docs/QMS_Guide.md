# QMS Guide

## Overview
This guide consolidates the QMS checklist template flow, external report uploads, comment system, and deployment steps.

## Templates
- Default checklist template: `backend/templates/Synthesis_QMS.xlsx`
- External JSON report example: `backend/templates/syn_qms.json`

## Default Checklist Creation
- For **existing** block + experiment pairs, backfill creates one checklist using the default template.
- For **new** experiments created via setup (`/api/projects/save-run-directory`), a default checklist is created automatically.
- Checklist naming follows: `blockname_tagname_expname` (or `blockname_expname` if no tag).

## External JSON Upload
Endpoint: **POST** `/api/qms/external-checklists/upload-report`  
Auth: **X-API-Key** header

### Required Identifiers
External uploads must match checklist parent details:
- `project` (or `project_name`)
- `block_name`
- `experiment` (or inferred from `stage_directory`)
- **Domain** inferred from `stage_directory`

Example `stage_directory`:
```
/CX_PROJ/ganga/pd/users/bhavya/tag2/aes_cipher_top2/exp2/syn
```
Domain is the segment after the 3rd slash → `pd`.

If the extracted domain does not belong to the project’s active domains, the upload is blocked.

### Request Examples
Multipart file upload:
```bash
curl -X POST "http://<backend-host>/api/qms/external-checklists/upload-report" \
  -H "X-API-Key: <API_KEY>" \
  -F "file=@/path/to/syn_qms.json"
```

Raw JSON body:
```bash
curl -X POST "http://<backend-host>/api/qms/external-checklists/upload-report" \
  -H "X-API-Key: <API_KEY>" \
  -H "Content-Type: application/json" \
  --data-binary "@/path/to/syn_qms.json"


  
curl.exe -X POST "http://localhost:3000/api/qms/external-checklists/upload-report" -H "X-API-Key: sitedafilesdata" -F "file=@backend/templates/syn_qms.json"
cd C:\Users\ganga\OneDrive\Desktop\ASI-Dashboard\ASI-dashboard
curl.exe -X POST "http://15.207.235.35:3000/api/qms/external-checklists/upload-report" -H "X-API-Key: sitedafilesdata" -F "file=@backend/templates/sys_qms1.json"
```

### Behavior
- Updates only matching Check IDs.
- Updates `check_name` only if present in JSON.
- Returns `missing_check_ids` and `extra_check_ids`.
- Resets checklist to `draft` (forces engineer resubmission).

### Status Management
Only **external JSON uploads** update `c_report_data.status`.
Internal flows (submit/approve/reject) **do not** update this field.

### State-Based Restrictions
Allowed checklist states:
- `pending`
- `draft`
- `rejected`

Blocked:
- `submitted_for_approval`
- `approved`

### Version-Based Restrictions
If RTL tags follow `{prefix}_v{number}`, uploads to older versions are blocked when a newer version is in progress (unless newer is approved).

## Comment System
Comments live in `check_items`:
- `comments` (JSON / external uploads only, read-only in UI)
- `engineer_comments` (editable by engineer, project manager, admin, lead)
- `reviewer_comments` (editable by approver/admin/lead/PM **only when checklist is submitted_for_approval**)

### API Endpoint
**PUT** `/api/qms/check-items/:checkItemId/comments`
```json
{
  "engineer_comments": "Optional engineer comments",
  "reviewer_comments": "Optional reviewer comments"
}
```

### UI
Columns:
- "Comments (JSON)" (read-only)
- "Engineer Comments" (editable when permitted)
- "Reviewer Comments" (editable when permitted)

## Approver Assignment
- Default approver is the project lead when a checklist is submitted.
- Assigned approver overrides default for that item.
- Approver remains tied to the approval record unless checklist is rejected and resubmitted.

## Deployment Steps
### 1) Templates
Ensure these files exist on host and in container:
```
/app/templates/Synthesis_QMS.xlsx
/app/templates/syn_qms.json
```

### 2) Database Migrations
Example:
```bash
docker exec -i asi_postgres psql -U postgres -d ASI < backend/migrations/031_add_check_name_remove_auto.sql
docker exec -i asi_postgres psql -U postgres -d ASI < backend/migrations/034_add_comments_to_check_items.sql
```

### 3) Backend Build + Restart
```bash
docker exec asi_backend npm run build
docker restart asi_backend
```

### 4) Frontend Build
```bash
cd frontend
flutter build web
```

### 5) Backfill Default Checklists
```bash
curl -X POST http://<backend-host>/api/qms/checklists/backfill-default-template \
  -H "Authorization: Bearer <ADMIN_TOKEN>"
```

## Testing Checklist
1. External upload succeeds for pending/draft/rejected checklists.
2. External upload blocked for submitted/approved checklists.
3. Domain mismatch blocks upload.
4. Version blocking works for `_vN` tags.
5. Engineer comments editable by engineer/PM/admin/lead.
6. Reviewer comments editable only during submitted_for_approval and by approver/admin/lead/PM.

## Code Locations
- Backend routes: `backend/src/routes/qms.routes.ts`
- External upload logic: `backend/src/services/qms.service.ts`
- Comment updates: `backend/src/services/qms.service.ts`
- Frontend UI: `frontend/lib/screens/qms_checklist_detail_screen.dart`

