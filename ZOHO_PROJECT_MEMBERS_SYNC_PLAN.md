# Zoho Project Members Sync - Implementation Plan

## Overview

This document outlines the implementation plan for syncing Zoho project members into the ASI Dashboard system, allowing users to have different roles per project.

---

## Requirements Summary

1. **Sync Members Button**: Fetch all users from a Zoho project and create/update them in ASI DB
2. **Zoho-Only Users**: Users synced from Zoho can only login via Zoho OAuth (no password)
3. **Project Assignment**: Assign users to projects in `user_projects` table
4. **Project-Specific Roles**: Role comes from Zoho Project profile (not Zoho People designation)
5. **Multi-Role Support**: Same user can have different roles in different projects

---

## Database Changes

### Migration: Add `role` column to `user_projects` table

**File**: `backend/migrations/020_add_role_to_user_projects.sql`

```sql
-- Add role column to user_projects table
-- This allows users to have different roles per project
ALTER TABLE user_projects 
ADD COLUMN IF NOT EXISTS role VARCHAR(50);

-- Add comment explaining the column
COMMENT ON COLUMN user_projects.role IS 
  'Project-specific role. If NULL, uses users.role as fallback. Allows same user to have different roles in different projects.';

-- Create index for faster role-based queries
CREATE INDEX IF NOT EXISTS idx_user_projects_role ON user_projects(role);

-- Update existing records: set role to NULL (will use users.role as fallback)
-- This maintains backward compatibility
UPDATE user_projects SET role = NULL WHERE role IS NULL;
```

**Why this design?**
- `user_projects.role` = project-specific role (from Zoho Project)
- `users.role` = default/primary role (from Zoho People or manual assignment)
- If `user_projects.role` is NULL, system falls back to `users.role`
- Allows same user to be "engineer" in Project A and "lead" in Project B

---

## Backend Implementation

### 1. Zoho Service: Add Project Members Methods

**File**: `backend/src/services/zoho.service.ts`

#### 1.1. Add Interface for Project Member

```typescript
interface ZohoProjectMember {
  id: string;
  name: string;
  email: string;
  role: string; // Project role: "Admin", "Manager", "Employee", etc.
  status: string; // "active", "inactive", etc.
  [key: string]: any;
}
```

#### 1.2. Add Method: `getProjectMembers`

```typescript
/**
 * Get all members/users for a Zoho project
 * @param userId - ASI user ID (for token retrieval)
 * @param projectId - Zoho project ID
 * @param portalId - Zoho portal ID (optional)
 * @returns Array of project members with their roles
 */
async getProjectMembers(
  userId: number,
  projectId: string,
  portalId?: string
): Promise<ZohoProjectMember[]> {
  try {
    const client = await this.getAuthenticatedClient(userId);
    
    let portal = portalId;
    if (!portal) {
      const portals = await this.getPortals(userId);
      if (portals.length === 0) {
        throw new Error('No portals found.');
      }
      portal = portals[0].id;
    }

    // Zoho Projects API endpoint for project members
    const response = await client.get(
      `/restapi/portal/${portal}/projects/${projectId}/users/`
    );

    // Handle different response structures
    let members: ZohoProjectMember[] = [];
    
    if (response.data.response?.result?.users) {
      members = response.data.response.result.users;
    } else if (response.data.response?.result?.project_users) {
      members = response.data.response.result.project_users;
    } else if (response.data.users) {
      members = response.data.users;
    } else if (response.data.project_users) {
      members = response.data.project_users;
    } else if (Array.isArray(response.data)) {
      members = response.data;
    }

    return members;
  } catch (error: any) {
    console.error('Error fetching project members:', error.response?.data || error.message);
    throw new Error(
      `Failed to fetch project members: ${error.response?.data?.error?.message || error.message}`
    );
  }
}
```

#### 1.3. Add Method: Map Zoho Project Role to ASI Role

```typescript
/**
 * Map Zoho Project role to ASI app role
 * @param zohoProjectRole - Role from Zoho Project (e.g., "Admin", "Manager", "Employee")
 * @returns ASI role: 'admin', 'project_manager', 'lead', 'engineer', 'customer'
 */
mapZohoProjectRoleToAppRole(zohoProjectRole: string | undefined): string {
  if (!zohoProjectRole) {
    return 'engineer'; // Default
  }

  const roleLower = zohoProjectRole.toLowerCase().trim();
  
  // Admin roles in Zoho Project
  const adminKeywords = [
    'admin', 'administrator', 'owner', 'project owner'
  ];
  
  // Project Manager roles
  const projectManagerKeywords = [
    'manager', 'project manager', 'pm', 'program manager'
  ];
  
  // Lead roles
  const leadKeywords = [
    'lead', 'team lead', 'tech lead', 'architect', 'senior'
  ];
  
  // Engineer roles
  const engineerKeywords = [
    'engineer', 'developer', 'employee', 'member', 'contributor'
  ];
  
  // Customer roles
  const customerKeywords = [
    'customer', 'client', 'stakeholder', 'viewer', 'read-only'
  ];

  if (adminKeywords.some(keyword => roleLower.includes(keyword))) {
    return 'admin';
  }
  
  if (projectManagerKeywords.some(keyword => roleLower.includes(keyword))) {
    return 'project_manager';
  }
  
  if (leadKeywords.some(keyword => roleLower.includes(keyword))) {
    return 'lead';
  }
  
  if (customerKeywords.some(keyword => roleLower.includes(keyword))) {
    return 'customer';
  }
  
  // Default to engineer
  return 'engineer';
}
```

#### 1.4. Add Method: `syncProjectMembers`

```typescript
/**
 * Sync Zoho project members to ASI database
 * - Creates users if they don't exist (Zoho-only users)
 * - Assigns users to project in user_projects table
 * - Sets project-specific role from Zoho Project
 * 
 * @param asiProjectId - ASI project ID (local database)
 * @param zohoProjectId - Zoho project ID
 * @param portalId - Zoho portal ID (optional)
 * @param syncedByUserId - User ID who initiated the sync
 * @returns Summary of sync operation
 */
async syncProjectMembers(
  asiProjectId: number,
  zohoProjectId: string,
  portalId: string | undefined,
  syncedByUserId: number
): Promise<{
  totalMembers: number;
  createdUsers: number;
  updatedAssignments: number;
  errors: Array<{ email: string; error: string }>;
}> {
  const { pool } = await import('../config/database');
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');

    // Get project members from Zoho
    const zohoMembers = await this.getProjectMembers(
      syncedByUserId,
      zohoProjectId,
      portalId
    );

    let createdUsers = 0;
    let updatedAssignments = 0;
    const errors: Array<{ email: string; error: string }> = [];

    for (const member of zohoMembers) {
      try {
        const email = member.email || member.Email || member.mail;
        const name = member.name || member.Name || member.full_name || email?.split('@')[0] || 'Unknown';
        const zohoRole = member.role || member.Role || member.project_role || 'Employee';
        
        if (!email) {
          errors.push({
            email: 'N/A',
            error: 'Member missing email address'
          });
          continue;
        }

        // Map Zoho Project role to ASI role
        const asiRole = this.mapZohoProjectRoleToAppRole(zohoRole);

        // Check if user exists
        const userCheck = await client.query(
          'SELECT id, role FROM users WHERE email = $1',
          [email]
        );

        let userId: number;

        if (userCheck.rows.length === 0) {
          // Create new user (Zoho-only user)
          const insertResult = await client.query(
            `INSERT INTO users (
              username, email, password_hash, full_name, role, is_active
            ) VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING id`,
            [
              email.split('@')[0], // username from email
              email,
              'zoho_oauth_user', // Zoho-only users can't login with password
              name,
              asiRole, // Default role (can be overridden per project)
              true
            ]
          );
          userId = insertResult.rows[0].id;
          createdUsers++;
        } else {
          userId = userCheck.rows[0].id;
          // Update name if changed (but keep existing role as default)
          await client.query(
            'UPDATE users SET full_name = COALESCE($1, full_name) WHERE id = $2',
            [name, userId]
          );
        }

        // Assign user to project with project-specific role
        // Use INSERT ... ON CONFLICT to update role if assignment already exists
        await client.query(
          `INSERT INTO user_projects (user_id, project_id, role)
           VALUES ($1, $2, $3)
           ON CONFLICT (user_id, project_id)
           DO UPDATE SET role = EXCLUDED.role`,
          [userId, asiProjectId, asiRole]
        );
        
        updatedAssignments++;

      } catch (memberError: any) {
        errors.push({
          email: member.email || 'N/A',
          error: memberError.message
        });
        console.error(`Error syncing member ${member.email}:`, memberError);
      }
    }

    await client.query('COMMIT');

    return {
      totalMembers: zohoMembers.length,
      createdUsers,
      updatedAssignments,
      errors
    };

  } catch (error: any) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
```

---

### 2. API Routes

**File**: `backend/src/routes/zoho.routes.ts`

#### 2.1. GET Project Members (Preview)

```typescript
/**
 * GET /api/zoho/projects/:zohoProjectId/members
 * Get all members for a Zoho project (preview before sync)
 */
router.get(
  '/projects/:zohoProjectId/members',
  authenticate,
  async (req, res) => {
    try {
      const userId = (req as any).user?.id;
      const { zohoProjectId } = req.params;
      const { portalId } = req.query;

      const members = await zohoService.getProjectMembers(
        userId,
        zohoProjectId,
        portalId as string | undefined
      );

      // Map roles for preview
      const mappedMembers = members.map(member => ({
        email: member.email || member.Email,
        name: member.name || member.Name,
        zoho_role: member.role || member.Role || 'Employee',
        asi_role: zohoService.mapZohoProjectRoleToAppRole(
          member.role || member.Role
        )
      }));

      res.json({
        success: true,
        count: mappedMembers.length,
        members: mappedMembers
      });
    } catch (error: any) {
      console.error('Error fetching project members:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
);
```

#### 2.2. POST Sync Members

**File**: `backend/src/routes/project.routes.ts`

```typescript
/**
 * POST /api/projects/:projectId/sync-zoho-members
 * Sync members from Zoho project to ASI project
 * Requires: projectId (ASI), zohoProjectId, portalId (optional)
 */
router.post(
  '/:projectId/sync-zoho-members',
  authenticate,
  authorize('admin', 'project_manager', 'lead'),
  async (req, res) => {
    try {
      const projectId = parseInt(req.params.projectId, 10);
      const userId = (req as any).user?.id;
      const { zohoProjectId, portalId } = req.body;

      if (isNaN(projectId)) {
        return res.status(400).json({ error: 'Invalid project ID' });
      }

      if (!zohoProjectId) {
        return res.status(400).json({ error: 'zohoProjectId is required' });
      }

      // Verify project exists
      const projectCheck = await pool.query(
        'SELECT id, name FROM projects WHERE id = $1',
        [projectId]
      );

      if (projectCheck.rows.length === 0) {
        return res.status(404).json({ error: 'Project not found' });
      }

      // Import zohoService
      const zohoService = (await import('../services/zoho.service')).default;

      // Sync members
      const result = await zohoService.syncProjectMembers(
        projectId,
        zohoProjectId,
        portalId,
        userId
      );

      res.json({
        success: true,
        message: 'Project members synced successfully',
        ...result
      });
    } catch (error: any) {
      console.error('Error syncing project members:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
);
```

---

### 3. Update Project Access Logic

**File**: `backend/src/services/qms.service.ts` and `backend/src/routes/project.routes.ts`

Update queries to check `user_projects.role` first, then fallback to `users.role`:

```typescript
// Example: In getFilterOptions or getChecklistsForBlock
// Use COALESCE to prefer project-specific role
const roleQuery = `
  SELECT 
    u.id,
    u.username,
    u.email,
    u.full_name,
    COALESCE(up.role, u.role) as effective_role
  FROM users u
  LEFT JOIN user_projects up ON up.user_id = u.id AND up.project_id = $1
  WHERE u.id = $2
`;
```

---

## Frontend Implementation

### 1. Add Sync Button Component

**File**: `frontend/lib/widgets/sync_zoho_members_button.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SyncZohoMembersButton extends ConsumerStatefulWidget {
  final int projectId;
  final String? zohoProjectId;
  final String? portalId;
  final VoidCallback? onSyncComplete;

  const SyncZohoMembersButton({
    Key? key,
    required this.projectId,
    this.zohoProjectId,
    this.portalId,
    this.onSyncComplete,
  }) : super(key: key);

  @override
  ConsumerState<SyncZohoMembersButton> createState() => _SyncZohoMembersButtonState();
}

class _SyncZohoMembersButtonState extends ConsumerState<SyncZohoMembersButton> {
  bool _isSyncing = false;

  Future<void> _syncMembers() async {
    if (widget.zohoProjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Zoho Project ID is required'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      final authState = ref.read(authProvider);
      final token = authState.token;

      if (token == null) {
        throw Exception('Not authenticated');
      }

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/projects/${widget.projectId}/sync-zoho-members'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'zohoProjectId': widget.zohoProjectId,
          'portalId': widget.portalId,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Synced ${data['updatedAssignments']} members. '
              'Created ${data['createdUsers']} new users.'
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
        widget.onSyncComplete?.call();
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to sync members');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error syncing members: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _isSyncing || widget.zohoProjectId == null ? null : _syncMembers,
      icon: _isSyncing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.sync),
      label: Text(_isSyncing ? 'Syncing...' : 'Sync Members from Zoho'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF14B8A6),
        foregroundColor: Colors.white,
      ),
    );
  }
}
```

### 2. Add to Project Details Screen

**File**: `frontend/lib/screens/project_management_screen.dart` (or wherever project details are shown)

```dart
// In project details widget, add:
if (project['source'] == 'zoho' && project['zoho_project_id'] != null)
  SyncZohoMembersButton(
    projectId: project['id'],
    zohoProjectId: project['zoho_project_id'].toString(),
    portalId: project['portal_id'],
    onSyncComplete: () {
      // Refresh project data
      _loadProjects();
    },
  ),
```

---

## Testing Checklist

- [ ] Migration runs successfully (`020_add_role_to_user_projects.sql`)
- [ ] `GET /api/zoho/projects/:zohoProjectId/members` returns project members
- [ ] `POST /api/projects/:projectId/sync-zoho-members` creates users and assigns to project
- [ ] New users have `password_hash = 'zoho_oauth_user'`
- [ ] Users can only login via Zoho OAuth (not username/password)
- [ ] Same user can have different roles in different projects
- [ ] Project access logic uses `user_projects.role` when available
- [ ] Frontend sync button works and shows success/error messages

---

## Next Steps After Implementation

1. **Role Management UI**: Add UI to manually change `user_projects.role` per project
2. **Bulk Role Update**: Allow admins to update roles for multiple users at once
3. **Sync History**: Track when syncs happened and who initiated them
4. **Auto-Sync**: Option to auto-sync members periodically (cron job)

---

## Notes

- **Zoho Project Role Mapping**: The mapping function can be customized based on your Zoho Projects role names
- **Error Handling**: The sync method continues even if some members fail (logs errors)
- **Backward Compatibility**: Existing `user_projects` records with `role = NULL` will use `users.role` as fallback
- **Security**: Only admins, project managers, and leads can trigger sync (authorize middleware)


