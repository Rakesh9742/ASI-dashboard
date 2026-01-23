# Role Management & Zoho Integration Documentation

## Table of Contents
1. [Overview](#overview)
2. [Role Management System](#role-management-system)
3. [Zoho OAuth Authentication](#zoho-oauth-authentication)
4. [Zoho Projects Integration](#zoho-projects-integration)
5. [API Endpoints](#api-endpoints)
6. [Database Schema](#database-schema)
7. [Authentication Flows](#authentication-flows)
8. [Project-Specific Role Assignment](#project-specific-role-assignment)

---

## Overview

This system implements a dual-role management system:
- **Global Roles**: Stored in `users.role` - applies system-wide
- **Project-Specific Roles**: Stored in `user_projects.role` - applies to specific projects

Users can have different roles in different projects. For example:
- User A: Global role `engineer`, Project 1 role `lead`, Project 2 role `engineer`
- User B: Global role `engineer`, Project 1 role `engineer`, Project 2 role `project_manager`

The system also integrates with Zoho for:
- OAuth authentication (Zoho People)
- Project member synchronization (Zoho Projects)
- Role mapping from Zoho project profiles

---

## Role Management System

### Role Hierarchy

1. **admin** - Full system access, can manage all projects and users
2. **project_manager** - Can manage projects, assign users, approve QMS checklists
3. **lead** - Can view lead/engineer views, approve QMS checklists
4. **engineer** - Default role, can create projects, submit QMS checklists
5. **customer** - Read-only access to assigned projects

### Global vs Project-Specific Roles

#### Global Role (`users.role`)
- Set during user creation or via admin update
- Used as default when no project-specific role exists
- Determines system-wide permissions
- For Zoho users: Defaults to `engineer` when synced

#### Project-Specific Role (`user_projects.role`)
- Set when user is assigned to a project
- Overrides global role for that specific project
- Allows same user to have different roles in different projects
- Synced from Zoho Projects when using "Sync Members from Zoho"

### Role Resolution Logic

When determining a user's effective role for a project:

```typescript
// Pseudo-code
function getEffectiveRole(userId, projectId) {
  // 1. Check project-specific role first
  const projectRole = user_projects.find(userId, projectId)?.role;
  if (projectRole) return projectRole;
  
  // 2. Fall back to global role
  return users.find(userId)?.role;
}
```

### View Type Access Based on Role

| Role | Available View Types |
|------|---------------------|
| `engineer` | Engineer View only |
| `lead` | Engineer View + Lead View |
| `project_manager` | Engineer View + Lead View + Manager View |
| `admin` | Engineer View + Lead View + Manager View |
| `customer` | Engineer View + Customer View |

---

## Zoho OAuth Authentication

### Overview

The system supports OAuth 2.0 authentication with Zoho, allowing users to:
- Login with their Zoho account
- Automatically create accounts in the system
- Sync profile information from Zoho People

### OAuth Flow

```
1. User clicks "Login with Zoho"
   ↓
2. Frontend calls GET /api/zoho/auth-url
   ↓
3. Backend generates authorization URL with scopes
   ↓
4. User redirected to Zoho authorization page
   ↓
5. User grants permissions
   ↓
6. Zoho redirects to /api/zoho/callback?code=xxx&state=login_xxx
   ↓
7. Backend exchanges code for access_token + refresh_token
   ↓
8. Backend fetches user info from Zoho People API
   ↓
9. Backend creates/updates user in database
   ↓
10. Backend generates JWT token
   ↓
11. User logged in with JWT token (valid 7 days)
```

### Required OAuth Scopes

```typescript
const scopes = [
  'AaaServer.profile.read',      // Basic profile
  'profile',                      // Profile information
  'email',                        // Email address
  'ZohoProjects.projects.READ',   // Read Zoho Projects
  'ZohoProjects.portals.READ',    // Read Zoho Portals
  'ZohoProjects.tasks.READ',      // Read tasks
  'ZohoProjects.tasklists.READ',  // Read task lists
  'ZohoProjects.users.READ',      // Read project users/members
  'ZOHOPEOPLE.forms.ALL',         // Access Zoho People forms
  'ZOHOPEOPLE.employee.ALL',      // Access employee records
];
```

### Environment Variables

```bash
ZOHO_CLIENT_ID=your_client_id
ZOHO_CLIENT_SECRET=your_client_secret
ZOHO_REDIRECT_URI=http://localhost:3000/api/zoho/callback
ZOHO_API_URL=https://projectsapi.zoho.com  # or .eu, .in, .com.au
ZOHO_AUTH_URL=https://accounts.zoho.com    # or .eu, .in, .com.au
```

### Token Management

#### Access Token
- Short-lived (typically 1 hour)
- Used for API calls
- Automatically refreshed when expired

#### Refresh Token
- Long-lived (doesn't expire)
- Stored in `zoho_tokens` table
- Used to get new access tokens

#### Token Storage

```sql
CREATE TABLE zoho_tokens (
  user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  access_token TEXT NOT NULL,
  refresh_token TEXT NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### User Creation from Zoho

When a user logs in with Zoho for the first time:

1. **Fetch User Info** from Zoho People API
2. **Extract Role/Designation** from Zoho People employee record
3. **Map Zoho Role to App Role**:
   - "Admin" → `admin`
   - "Manager" → `project_manager`
   - "Lead" → `lead`
   - "Employee" → `engineer`
   - Default → `engineer`
4. **Create User** in database:
   - Email from Zoho
   - Full name from Zoho
   - Role from Zoho People designation
   - `password_hash` = `'zoho_oauth_user'` (indicates Zoho-only user)
5. **Store Tokens** in `zoho_tokens` table

---

## Zoho Projects Integration

### Overview

The system can sync project members from Zoho Projects to the local database, maintaining:
- User accounts (if they don't exist)
- Project assignments
- Project-specific roles

### Sync Members Flow

```
1. Admin/PM/Lead clicks "Sync Members from Zoho" button
   ↓
2. Frontend calls POST /api/projects/:projectId/sync-zoho-members
   ↓
3. Backend validates user permissions
   ↓
4. Backend calls Zoho Projects API to get project members
   ↓
5. For each member:
   a. Check if user exists (by email)
   b. If not exists: Create user with role='engineer'
   c. Get project-specific role from Zoho
   d. Map Zoho role to app role
   e. Insert/Update user_projects with project-specific role
   ↓
6. Return sync results (created, updated, errors)
```

### Zoho Projects API Endpoints Used

#### Get Project Members
```
GET /api/v3/portal/{portalId}/projects/{projectId}/users/
```

**Fallback endpoints** (if V3 fails):
- `/restapi/portal/{portalId}/projects/{projectId}/users/`
- `/api/v3/portal/{portalId}/projects/{projectId}/people/`
- `/restapi/portal/{portalId}/projects/{projectId}/people/`
- `/api/v3/portal/{portalId}/projects/{projectId}/members/`
- `/restapi/portal/{portalId}/projects/{projectId}/members/`

#### Response Structure
```json
{
  "users": [
    {
      "id": "123456789",
      "name": "John Doe",
      "email": "john@example.com",
      "role": "Admin",  // or "Manager", "Employee", etc.
      "status": "active"
    }
  ]
}
```

### Role Mapping from Zoho

Zoho project roles are mapped to application roles:

| Zoho Role | App Role |
|-----------|----------|
| Admin | `admin` |
| Manager | `project_manager` |
| Lead | `lead` |
| Employee | `engineer` |
| Customer | `customer` |
| Default | `engineer` |

**Implementation:**
```typescript
mapZohoProjectRoleToAppRole(zohoRole: string): string {
  const roleLower = zohoRole.toLowerCase().trim();
  
  if (roleLower.includes('admin')) return 'admin';
  if (roleLower.includes('manager')) return 'project_manager';
  if (roleLower.includes('lead')) return 'lead';
  if (roleLower.includes('customer')) return 'customer';
  
  return 'engineer'; // Default
}
```

### Portal Detection

The system automatically detects the correct Zoho portal by:
1. Fetching all available portals
2. Searching each portal for the target project
3. Matching project ID (supports both `id` and `id_string` formats)
4. Using the portal that contains the project

---

## API Endpoints

### Authentication Endpoints

#### GET /api/zoho/auth-url
Get Zoho OAuth authorization URL.

**Request:**
```http
GET /api/zoho/auth-url
Authorization: Bearer <jwt_token>
```

**Response:**
```json
{
  "authUrl": "https://accounts.zoho.com/oauth/v2/auth?..."
}
```

#### GET /api/zoho/callback
OAuth callback endpoint (called by Zoho).

**Query Parameters:**
- `code` - Authorization code
- `state` - State parameter (contains user context)
- `error` - Error code (if authorization failed)

**Response:**
- HTML page with success/error message
- Automatically creates/updates user
- Stores OAuth tokens

#### POST /api/auth/login
Traditional username/password login.

**Request:**
```json
{
  "username": "user@example.com",
  "password": "password123"
}
```

**Response:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": 1,
    "username": "user@example.com",
    "email": "user@example.com",
    "full_name": "John Doe",
    "role": "engineer"
  }
}
```

#### POST /api/auth/set-password
Set password for Zoho OAuth users (optional).

**Request:**
```json
{
  "password": "newpassword123"
}
```

**Response:**
```json
{
  "message": "Password set successfully"
}
```

### Project Endpoints

#### GET /api/projects/:projectIdentifier/user-role
Get user's role for a specific project.

**Request:**
```http
GET /api/projects/Ganga/user-role
Authorization: Bearer <jwt_token>
```

**Response:**
```json
{
  "success": true,
  "globalRole": "engineer",
  "projectRole": "lead",
  "effectiveRole": "lead",
  "availableViewTypes": ["engineer", "lead"],
  "asiProjectId": 13
}
```

#### POST /api/projects/:projectId/sync-zoho-members
Sync members from Zoho project to ASI project.

**Request:**
```http
POST /api/projects/13/sync-zoho-members
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "zohoProjectId": "173458000001945100",
  "portalId": "60021787257"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Synced 5 members successfully",
  "stats": {
    "total": 5,
    "created": 2,
    "updated": 3,
    "errors": 0
  }
}
```

**Required Roles:** `admin`, `project_manager`, or `lead`

### Zoho Endpoints

#### GET /api/zoho/status
Check Zoho connection status.

**Response:**
```json
{
  "connected": true,
  "user": {
    "email": "user@example.com",
    "name": "John Doe"
  }
}
```

#### GET /api/zoho/projects
Get all Zoho projects.

**Query Parameters:**
- `portalId` (optional) - Specific portal ID

**Response:**
```json
{
  "success": true,
  "count": 10,
  "projects": [...]
}
```

#### GET /api/zoho/projects/:projectId/members
Preview project members from Zoho.

**Response:**
```json
{
  "success": true,
  "members": [
    {
      "id": "123456789",
      "name": "John Doe",
      "email": "john@example.com",
      "role": "Admin"
    }
  ]
}
```

---

## Database Schema

### Users Table

```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(100) UNIQUE NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  full_name VARCHAR(255),
  role user_role NOT NULL DEFAULT 'engineer',  -- Global role
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_login TIMESTAMP
);
```

**Note:** `password_hash = 'zoho_oauth_user'` indicates a Zoho-only user.

### User Projects Table

```sql
CREATE TABLE user_projects (
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
  role VARCHAR(50) DEFAULT 'engineer',  -- Project-specific role
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, project_id)
);

COMMENT ON COLUMN user_projects.role IS 'Project-specific role for the user in this project';
```

**Key Points:**
- Composite primary key: `(user_id, project_id)`
- Allows same user to have different roles in different projects
- Role defaults to `'engineer'` if not specified

### Zoho Tokens Table

```sql
CREATE TABLE zoho_tokens (
  user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  access_token TEXT NOT NULL,
  refresh_token TEXT NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Projects Table

```sql
CREATE TABLE projects (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  client VARCHAR(255),
  technology_node VARCHAR(100),
  start_date DATE,
  target_date DATE,
  plan TEXT,
  created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Zoho Projects Mapping Table

```sql
CREATE TABLE zoho_projects_mapping (
  zoho_project_id VARCHAR(255) PRIMARY KEY,
  asi_project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
  portal_id VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

---

## Authentication Flows

### Flow 1: Zoho OAuth Login (First Time)

```
1. User → Frontend: Click "Login with Zoho"
2. Frontend → Backend: GET /api/zoho/auth-url?state=login_<session_id>
3. Backend → Zoho: Redirect to authorization URL
4. User → Zoho: Grant permissions
5. Zoho → Backend: GET /api/zoho/callback?code=xxx&state=login_xxx
6. Backend → Zoho: Exchange code for tokens
7. Backend → Zoho People API: Get user info
8. Backend → Database: Create user (if not exists)
9. Backend → Database: Store tokens
10. Backend → Frontend: Return JWT token
11. Frontend: Store JWT, redirect to dashboard
```

### Flow 2: Zoho OAuth Login (Existing User)

```
1-5. Same as Flow 1
6. Backend → Zoho: Exchange code for tokens
7. Backend → Database: Update tokens
8. Backend → Frontend: Return JWT token
9. Frontend: Store JWT, redirect to dashboard
```

### Flow 3: Username/Password Login

```
1. User → Frontend: Enter username/password
2. Frontend → Backend: POST /api/auth/login
3. Backend → Database: Verify credentials
4. Backend → Frontend: Return JWT token
5. Frontend: Store JWT, redirect to dashboard
```

### Flow 4: Token Refresh

```
1. Frontend → Backend: API call with expired token
2. Backend: Detect expired token
3. Backend → Database: Get refresh_token
4. Backend → Zoho: POST /oauth/v2/token (refresh_token grant)
5. Backend → Database: Update access_token
6. Backend → Frontend: Return new token or retry request
```

---

## Project-Specific Role Assignment

### Manual Assignment

Admins can manually assign users to projects with specific roles:

```sql
INSERT INTO user_projects (user_id, project_id, role)
VALUES (1, 13, 'lead')
ON CONFLICT (user_id, project_id)
DO UPDATE SET role = EXCLUDED.role;
```

### Automatic Assignment via Zoho Sync

When syncing members from Zoho:

1. **Fetch Members** from Zoho Projects API
2. **For Each Member:**
   - Extract email, name, and project role
   - Check if user exists (by email)
   - If not exists: Create user with `role='engineer'`
   - Map Zoho role to app role
   - Insert/Update `user_projects` with project-specific role

**Example:**
```typescript
// Zoho member: { email: "john@example.com", role: "Admin" }
// Mapped to: user_projects.role = "admin"
// Global role: users.role = "engineer" (default for new users)
```

### Role Resolution in API

When checking user permissions for a project:

```typescript
// Get effective role
const projectRole = await pool.query(
  'SELECT role FROM user_projects WHERE user_id = $1 AND project_id = $2',
  [userId, projectId]
);

const effectiveRole = projectRole.rows[0]?.role || globalRole;
```

### View Type Filtering

The frontend filters available view types based on effective role:

```dart
// Pseudo-code
List<String> getAvailableViewTypes(String effectiveRole) {
  switch (effectiveRole) {
    case 'engineer':
      return ['engineer'];
    case 'lead':
      return ['engineer', 'lead'];
    case 'project_manager':
    case 'admin':
      return ['engineer', 'lead', 'manager'];
    case 'customer':
      return ['engineer', 'customer'];
    default:
      return ['engineer'];
  }
}
```

---

## Best Practices

### 1. Token Management
- Always store refresh tokens securely
- Implement automatic token refresh
- Handle token expiration gracefully

### 2. Role Assignment
- Use project-specific roles for fine-grained access control
- Keep global roles as defaults
- Document role changes in audit logs

### 3. Zoho Sync
- Run sync periodically to keep roles in sync
- Handle API errors gracefully
- Log sync operations for debugging

### 4. Security
- Never expose OAuth client secrets
- Use HTTPS for all OAuth callbacks
- Validate user permissions before API operations
- Sanitize user inputs

### 5. Error Handling
- Provide clear error messages
- Log errors for debugging
- Handle Zoho API rate limits
- Implement retry logic for transient failures

---

## Troubleshooting

### Common Issues

#### 1. OAuth Callback Fails
- **Check:** Redirect URI matches Zoho app configuration
- **Check:** Environment variables are set correctly
- **Check:** Zoho app has correct scopes enabled

#### 2. Token Refresh Fails
- **Check:** Refresh token is stored correctly
- **Check:** Token hasn't been revoked in Zoho
- **Check:** Client credentials are correct

#### 3. Role Not Syncing
- **Check:** Zoho project has members assigned
- **Check:** User has correct permissions in Zoho
- **Check:** API scopes include `ZohoProjects.users.READ`

#### 4. Project Members Not Found
- **Check:** Portal ID is correct
- **Check:** Project ID format (may need `id_string`)
- **Check:** User has access to the portal

---

## API Reference Summary

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/api/zoho/auth-url` | GET | Yes | Get OAuth authorization URL |
| `/api/zoho/callback` | GET | No | OAuth callback handler |
| `/api/zoho/status` | GET | Yes | Check Zoho connection |
| `/api/zoho/projects` | GET | Yes | List Zoho projects |
| `/api/zoho/projects/:id/members` | GET | Yes | Get project members |
| `/api/projects/:id/user-role` | GET | Yes | Get user's project role |
| `/api/projects/:id/sync-zoho-members` | POST | Yes | Sync members from Zoho |
| `/api/auth/login` | POST | No | Username/password login |
| `/api/auth/set-password` | POST | Yes | Set password (Zoho users) |

---

## Future Enhancements

1. **Role Templates**: Predefined role sets for common scenarios
2. **Role Inheritance**: Hierarchical role structures
3. **Audit Logging**: Track all role changes
4. **Bulk Role Assignment**: Assign roles to multiple users at once
5. **Role Expiration**: Time-based role assignments
6. **Custom Roles**: Project-specific custom roles

---

## Support

For issues or questions:
1. Check logs in `backend/logs/`
2. Review Zoho API documentation
3. Verify environment variables
4. Test OAuth flow manually
5. Check database for token/role data

---

**Last Updated:** 2025-01-XX
**Version:** 1.0.0

