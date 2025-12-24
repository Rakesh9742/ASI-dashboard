# Projects API Response Structure

This document describes the API response structure when fetching projects from `/api/projects?includeZoho=true`.

## API Endpoint

**GET** `/api/projects?includeZoho=true`

**Headers:**
- `Authorization: Bearer <token>` (required)

## Response Structure

The API returns a JSON object with the following structure:

```json
{
  "local": [...],      // Array of local projects
  "zoho": [...],       // Array of Zoho projects
  "all": [...],        // Combined array of all projects
  "counts": {
    "local": 5,
    "zoho": 10,
    "total": 15
  }
}
```

---

## Local Project Structure

Each local project in the `local` array has the following structure:

```json
{
  "id": 1,
  "name": "Project Name",
  "client": "Client Name",
  "technology_node": "7nm",
  "start_date": "2024-01-01T00:00:00.000Z",
  "target_date": "2024-12-31T00:00:00.000Z",
  "plan": "Project description/plan",
  "created_at": "2024-01-01T00:00:00.000Z",
  "updated_at": "2024-01-01T00:00:00.000Z",
  "created_by": 123,
  "source": "local",
  "domains": [
    {
      "id": 1,
      "name": "Domain Name",
      "code": "DOMAIN_CODE",
      "description": "Domain description"
    }
  ]
}
```

### Local Project Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | number | Unique project ID |
| `name` | string | Project name |
| `client` | string \| null | Client name |
| `technology_node` | string | Technology node (e.g., "7nm", "5nm") |
| `start_date` | string \| null | Project start date (ISO 8601) |
| `target_date` | string \| null | Project target/due date (ISO 8601) |
| `plan` | string \| null | Project description/plan |
| `created_at` | string | Creation timestamp (ISO 8601) |
| `updated_at` | string | Last update timestamp (ISO 8601) |
| `created_by` | number \| null | User ID who created the project |
| `source` | string | Always `"local"` for local projects |
| `domains` | array | Array of domain objects associated with the project |

---

## Zoho Project Structure

Each Zoho project in the `zoho` array has the following structure:

```json
{
  "id": "zoho_123456789",
  "name": "Zoho Project Name",
  "client": "Owner Name",
  "technology_node": null,
  "start_date": "2024-01-01T00:00:00.000Z",
  "target_date": "2024-12-31T00:00:00.000Z",
  "plan": "Project description",
  "created_at": "2024-01-01T00:00:00.000Z",
  "updated_at": "2024-01-01T00:00:00.000Z",
  "domains": [],
  "source": "zoho",
  "zoho_project_id": "123456789",
  "zoho_data": {
    // All fields from Zoho Projects API (see below)
  }
}
```

### Zoho Project Standard Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Prefixed with `"zoho_"` + Zoho project ID |
| `name` | string | Project name from Zoho |
| `client` | string \| null | Owner name from Zoho |
| `technology_node` | null | Always null for Zoho projects |
| `start_date` | string \| null | Project start date from Zoho |
| `target_date` | string \| null | Project end date from Zoho |
| `plan` | string \| null | Project description from Zoho |
| `created_at` | string \| null | Creation time from Zoho |
| `updated_at` | string \| null | Update time from Zoho |
| `domains` | array | Always empty array `[]` |
| `source` | string | Always `"zoho"` for Zoho projects |
| `zoho_project_id` | string | Original Zoho project ID |
| `zoho_data` | object | **Complete Zoho API response** (see below) |

---

## Zoho Data Object (`zoho_data`)

The `zoho_data` field contains the complete response from Zoho Projects API. This includes all fields returned by Zoho. Common fields include:

### Commonly Used Zoho Fields

| Field | Type | Description | Used in UI |
|-------|------|-------------|------------|
| `id` | string | Zoho project ID | Yes |
| `name` | string | Project name | Yes |
| `description` | string | Project description | Yes |
| `status` | string | Project status | Yes |
| `start_date` | string | Start date | Yes |
| `end_date` | string | End date | Yes |
| `owner_name` | string | Project owner name | Yes |
| `owner` | string | Owner ID | No |
| `created_by` | string | Creator ID | Yes |
| `created_by_name` | string | Creator name | Yes |
| `created_time` | string | Creation timestamp | Yes |
| `priority` | string | Priority level | Yes |
| `completion_percentage` | number | Completion % (0-100) | Yes |
| `work_hours` | string | Work hours (format: "HH:MM") | Yes |
| `work_hours_p` | string | Work hours formatted | Yes |
| `timelog_total` | string | Total timelog | Yes |
| `timelog_total_t` | string | Total timelog formatted | Yes |
| `billing_type` | string | Billing type | Yes |
| `associated_team` | string | Team ID | Yes |
| `team_name` | string | Team name | Yes |
| `completion_date` | string | Completion date | Yes |
| `tags` | array | Project tags | Yes |
| `tag_names` | array | Tag names | Yes |

### Additional Zoho Fields

The `zoho_data` object may contain many more fields depending on your Zoho Projects configuration. These can include:

- Custom fields configured in Zoho Projects
- Milestone information
- Task counts (e.g., `task_count`, `open_task_count`, `closed_task_count`)
- Budget information
- Resource allocation
- And any other fields returned by the Zoho Projects API

**Note:** 
- The frontend displays all available fields in the "All Zoho Project Fields" section when viewing project details.
- **Tasks are NOT included in the project response.** The API only returns project metadata. To fetch tasks for a project, you would need a separate API endpoint (not currently implemented).

### Task-Related Fields in zoho_data

While tasks themselves are not included, the `zoho_data` object may contain task-related metadata such as:

- `task_count` - Total number of tasks
- `open_task_count` - Number of open tasks
- `closed_task_count` - Number of closed tasks
- `milestone_count` - Number of milestones
- `bug_count` - Number of bugs/issues

These fields are included if Zoho Projects API returns them in the project response.

---

## Example Complete Response

```json
{
  "local": [
    {
      "id": 1,
      "name": "Local Project 1",
      "client": "Client A",
      "technology_node": "7nm",
      "start_date": "2024-01-01T00:00:00.000Z",
      "target_date": "2024-12-31T00:00:00.000Z",
      "plan": "Project plan description",
      "created_at": "2024-01-01T00:00:00.000Z",
      "updated_at": "2024-01-01T00:00:00.000Z",
      "created_by": 123,
      "source": "local",
      "domains": [
        {
          "id": 1,
          "name": "Domain 1",
          "code": "DOM1",
          "description": "Domain description"
        }
      ]
    }
  ],
  "zoho": [
    {
      "id": "zoho_123456789",
      "name": "Zoho Project 1",
      "client": "John Doe",
      "technology_node": null,
      "start_date": "2024-01-01T00:00:00.000Z",
      "target_date": "2024-12-31T00:00:00.000Z",
      "plan": "Zoho project description",
      "created_at": "2024-01-01T00:00:00.000Z",
      "updated_at": "2024-01-01T00:00:00.000Z",
      "domains": [],
      "source": "zoho",
      "zoho_project_id": "123456789",
      "zoho_data": {
        "id": "123456789",
        "name": "Zoho Project 1",
        "description": "Zoho project description",
        "status": "active",
        "start_date": "2024-01-01",
        "end_date": "2024-12-31",
        "owner_name": "John Doe",
        "owner": "987654321",
        "created_by": "111222333",
        "created_by_name": "Jane Smith",
        "created_time": "2024-01-01T00:00:00+00:00",
        "priority": "High",
        "completion_percentage": 45,
        "work_hours": "120:30",
        "work_hours_p": "120:30",
        "timelog_total": "100:00",
        "timelog_total_t": "100:00",
        "billing_type": "Fixed Price",
        "associated_team": "555666777",
        "team_name": "Development Team",
        "completion_date": null,
        "tags": ["urgent", "client-project"],
        "tag_names": ["urgent", "client-project"]
        // ... potentially many more fields from Zoho
      }
    }
  ],
  "all": [
    // Combined array of local and zoho projects
  ],
  "counts": {
    "local": 1,
    "zoho": 1,
    "total": 2
  }
}
```

---

## Frontend Usage

The frontend (`engineer_projects_screen.dart`) uses these fields to display:

1. **Table View:**
   - ID, Name, Source, Status
   - Start Date, Due Date, Duration
   - Owner, Created By
   - Completion %, Work Hours
   - Priority, Team, Billing Type, Timelog Total

2. **Project Details Dialog:**
   - Project Information section (standard fields)
   - Zoho-specific fields (from `zoho_data`)
   - All Zoho Project Fields section (shows all fields from `zoho_data`)

---

## Notes

- When `includeZoho=false` or not provided, only local projects are returned as a simple array
- Zoho projects are only included if the user has a valid Zoho token
- The `zoho_data` field contains the complete, unmodified response from Zoho Projects API
- All date fields are in ISO 8601 format
- The `domains` field is always empty for Zoho projects (domain mapping not implemented)

