# QMS Workflow Integration Plan

## Overview
This document outlines the plan to integrate the QMS (Quality Management System) workflow from the `develop-temp` branch into the current codebase.

## Current Status
- ✅ Zoho redirect URI issue is fixed
- ✅ Frontend UI has been updated (SemiconOS dashboard)
- ⏳ QMS workflow needs to be integrated from `develop-temp` branch

## Integration Steps

### Step 1: Identify QMS Components in develop-temp Branch

Check what QMS-related files exist in the develop-temp branch:

```bash
# List all QMS-related files
git ls-tree -r develop-temp --name-only | grep -i "qms\|checklist"

# Check backend routes
git show develop-temp:backend/src/routes/ --name-only | grep -i "qms"

# Check frontend screens
git show develop-temp:frontend/lib/screens/ --name-only | grep -i "qms"
```

### Step 2: Backend Integration

#### 2.1 QMS Routes
- Check if `qms.routes.ts` exists in develop-temp
- Copy to `backend/src/routes/qms.routes.ts`
- Register routes in `backend/src/index.ts`

#### 2.2 QMS Services
- Check if `qms.service.ts` exists in develop-temp
- Copy to `backend/src/services/qms.service.ts`
- Ensure database migrations are included

#### 2.3 Database Migrations
- Check for QMS-related migrations in develop-temp
- Copy migration files to `backend/migrations/`
- Run migrations:
  ```bash
  docker exec asi_postgres psql -U postgres -d ASI -f migrations/XXX_qms_schema.sql
  ```

### Step 3: Frontend Integration

#### 3.1 QMS Screens
- Check for QMS screens in develop-temp:
  - `qms_dashboard_screen.dart`
  - `qms_checklist_detail_screen.dart`
  - Any other QMS-related screens
- Copy to `frontend/lib/screens/`

#### 3.2 QMS Services
- Check for `qms_service.dart` in develop-temp
- Copy to `frontend/lib/services/qms_service.dart`
- Update API service if needed

#### 3.3 Navigation Integration
- Add QMS navigation to `main_navigation_screen.dart`
- Add QMS tab to the SemiconOS dashboard if needed
- Update routing logic

### Step 4: Testing

1. **Backend Testing**
   - Test QMS API endpoints
   - Verify database schema
   - Check authentication/authorization

2. **Frontend Testing**
   - Test QMS screens load correctly
   - Verify navigation works
   - Test QMS workflows (create, view, approve, etc.)

### Step 5: Merge Strategy

**Option A: Cherry-pick specific commits**
```bash
# Find QMS-related commits
git log develop-temp --oneline --grep="QMS\|qms\|checklist"

# Cherry-pick specific commits
git cherry-pick <commit-hash>
```

**Option B: Manual file copy**
```bash
# Checkout specific files from develop-temp
git checkout develop-temp -- backend/src/routes/qms.routes.ts
git checkout develop-temp -- frontend/lib/screens/qms_dashboard_screen.dart
# ... etc
```

**Option C: Create integration branch**
```bash
# Create new branch for integration
git checkout -b integrate-qms-workflow

# Merge develop-temp
git merge develop-temp --no-commit

# Resolve conflicts manually
# Keep current UI changes, integrate QMS functionality
```

## Files to Check in develop-temp Branch

### Backend
- `backend/src/routes/qms.routes.ts`
- `backend/src/services/qms.service.ts`
- `backend/migrations/*_qms*.sql`

### Frontend
- `frontend/lib/screens/qms_*.dart`
- `frontend/lib/services/qms_service.dart`
- Any QMS-related widgets or providers

## Integration Checklist

- [ ] Identify all QMS files in develop-temp branch
- [ ] Copy backend QMS routes and services
- [ ] Copy frontend QMS screens and services
- [ ] Run database migrations
- [ ] Register QMS routes in backend
- [ ] Add QMS navigation to frontend
- [ ] Update API service endpoints
- [ ] Test QMS workflows
- [ ] Resolve any conflicts with current UI
- [ ] Rebuild and restart containers
- [ ] Verify QMS functionality works

## Notes

- The current UI has changed (SemiconOS dashboard)
- Need to ensure QMS integrates seamlessly with the new UI
- May need to adapt QMS screens to match current design patterns
- Check for any dependencies or conflicts with existing code







