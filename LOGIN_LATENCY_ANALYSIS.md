# Login Latency Root Cause Analysis

## API Calls During Login Flow

### 1. Login Request (Backend)
- **POST /api/auth/login**
  - Database query: Verify credentials
  - Database query: Update last_login
  - **SSH Connection: getSSHConnection(userId)** ⚠️ **BLOCKING 2-5 seconds**
  - Generate JWT token
  - Return response

### 2. After Login (Frontend)
- Navigate to `MainNavigationScreen`
- `MainNavigationScreen` shows `ProjectsScreen` by default
- **ProjectsScreen.initState()** immediately calls:
  - `_loadProjects()` → `getProjectsWithZoho(includeZoho: true)`
    - Backend: `/api/projects?includeZoho=true`
      - Check Zoho token validity
      - Fetch Zoho portals (if not cached)
      - Fetch Zoho projects (if not cached)
      - Batch database queries for mappings/run directories
      - Return combined projects

### 3. Parallel/Duplicate Calls
- **dashboardProvider** (if watched):
  - `loadStats()` called automatically
  - Parallel calls:
    - `getProjects()` ⚠️ **DUPLICATE!**
    - `getDomains()`
    - `getDesigns()`
    - `getChips()`
  - Sequential call:
    - `getUsers()` (after parallel calls complete)

## Root Causes Identified

### 1. **SSH Connection Blocking Login** ⚠️ CRITICAL
- **Location**: `backend/src/routes/auth.routes.ts:226`
- **Impact**: 2-5 seconds delay during login
- **Issue**: SSH connection is established synchronously during login
- **Fix**: Make SSH connection non-blocking (establish in background)

### 2. **Duplicate Projects API Calls** ⚠️ HIGH
- **Location**: 
  - `ProjectsScreen._loadProjects()` calls `getProjectsWithZoho()`
  - `dashboardProvider.loadStats()` calls `getProjects()`
- **Impact**: 2x API calls, 2x database queries, 2x Zoho API calls (if not cached)
- **Fix**: Share projects data between components or lazy load dashboard

### 3. **dashboardProvider Loading Unnecessarily** ⚠️ MEDIUM
- **Location**: `frontend/lib/providers/dashboard_provider.dart:25`
- **Impact**: Loads stats even when dashboard not visible
- **Issue**: `loadStats()` called in constructor, even if provider not watched
- **Fix**: Lazy load - only load when actually watched

### 4. **Zoho Projects Always Loaded** ⚠️ MEDIUM
- **Location**: `ProjectsScreen._loadProjects()` always calls `getProjectsWithZoho(includeZoho: true)`
- **Impact**: Extra Zoho API calls even if user doesn't need Zoho projects
- **Fix**: Only load Zoho projects if user has Zoho connected

### 5. **Sequential User Fetch** ⚠️ LOW
- **Location**: `dashboardProvider.loadStats()` fetches users after parallel calls
- **Impact**: Additional sequential API call
- **Fix**: Include in parallel calls with error handling

## Performance Impact

### Current Flow (Worst Case)
1. Login: 2-5 seconds (SSH connection)
2. ProjectsScreen loads: 1-3 seconds (getProjectsWithZoho with Zoho)
3. dashboardProvider loads: 1-2 seconds (getProjects duplicate + other calls)
4. **Total: 4-10 seconds**

### After Optimizations (Expected)
1. Login: 0.1-0.3 seconds (SSH non-blocking)
2. ProjectsScreen loads: 0.5-1.5 seconds (cached, no duplicate)
3. dashboardProvider loads: 0.3-0.8 seconds (lazy, no duplicate projects)
4. **Total: 0.9-2.6 seconds (60-75% improvement)**

## Recommended Fixes Priority

1. **HIGH**: Make SSH connection non-blocking during login
2. **HIGH**: Eliminate duplicate projects API calls
3. **MEDIUM**: Lazy load dashboardProvider
4. **MEDIUM**: Conditional Zoho projects loading
5. **LOW**: Parallelize user fetch in dashboardProvider

