# Zoho Projects UI Integration Guide

This guide explains how users can authenticate with Zoho Projects and view their projects in the UI.

## Overview

The Zoho integration allows users to:
1. **Connect** their Zoho Projects account via OAuth
2. **View** Zoho projects alongside local projects
3. **Sync** project data from Zoho Projects

## User Flow

### Step 1: Access Zoho Integration

Users can access Zoho integration in two ways:

**Option A: From Project Management Screen**
- Navigate to **Projects** in the sidebar
- Click the **Settings icon** (⚙️) in the top right
- This opens the Zoho Integration screen

**Option B: Direct Navigation**
- The Zoho Integration screen can be accessed programmatically

### Step 2: Connect Zoho Account

1. **Open Zoho Integration Screen**
   - User sees connection status (Connected/Not Connected)
   - If not connected, a "Connect Zoho Projects" button is shown

2. **Click "Connect Zoho Projects"**
   - App requests authorization URL from backend
   - Backend returns: `http://localhost:3000/api/zoho/auth`
   - Response contains `authUrl` with OAuth URL

3. **OAuth Flow**
   - App opens the authorization URL in external browser
   - User logs into Zoho (if not already logged in)
   - User authorizes the application
   - Zoho redirects to: `http://localhost:3000/api/zoho/callback?code=...&state=userId`
   - Backend exchanges code for tokens
   - Tokens are saved to database

4. **Return to App**
   - User returns to the app
   - App automatically checks connection status
   - Status updates to "Connected"

### Step 3: View Zoho Projects

1. **Navigate to Projects Screen**
   - Go to **Projects** in the sidebar

2. **Toggle Zoho Projects**
   - If Zoho is connected, a **cloud icon** (☁️) appears in the header
   - Click the cloud icon to toggle Zoho projects visibility
   - When enabled, Zoho projects appear alongside local projects

3. **Project Display**
   - **Local Projects**: Purple cards with folder icon
   - **Zoho Projects**: Blue cards with cloud icon
   - Zoho projects show a "Zoho" badge
   - Projects are displayed in a grid layout

## UI Components

### 1. Zoho Integration Screen (`zoho_integration_screen.dart`)

**Features:**
- Connection status indicator
- Token expiration information
- Connect/Disconnect buttons
- Portal list (when connected)

**Key Methods:**
- `_checkStatus()` - Checks if Zoho is connected
- `_connectZoho()` - Initiates OAuth flow
- `_disconnectZoho()` - Removes Zoho connection
- `_loadPortals()` - Loads user's Zoho portals

### 2. Updated Project Management Screen

**New Features:**
- Zoho connection status check
- Toggle to show/hide Zoho projects
- Settings button to access Zoho integration
- Visual distinction between local and Zoho projects

**Key Methods:**
- `_checkZohoStatus()` - Checks Zoho connection
- `_loadDomainsAndProjects()` - Loads both local and Zoho projects
- `_buildProjectCard()` - Renders project cards with Zoho indicator

### 3. API Service Updates

**New Methods:**
- `getZohoAuthUrl()` - Gets OAuth authorization URL
- `getZohoStatus()` - Checks connection status
- `getZohoPortals()` - Gets user's portals
- `getZohoProjects()` - Gets projects from Zoho
- `disconnectZoho()` - Removes connection
- `getProjectsWithZoho()` - Gets combined projects

## Visual Indicators

### Connection Status
- ✅ **Green checkmark** = Connected
- ❌ **Red X** = Not Connected

### Project Cards
- **Purple gradient** = Local project
- **Blue gradient** = Zoho project
- **Cloud icon** = Zoho project indicator
- **"Zoho" badge** = Zoho project label

### Buttons
- **Connect** = Blue button to start OAuth
- **Disconnect** = Red button to remove connection
- **Cloud toggle** = Show/hide Zoho projects

## Technical Details

### OAuth Flow

```
User clicks "Connect"
    ↓
App calls: GET /api/zoho/auth
    ↓
Backend returns: { authUrl: "https://accounts.zoho.in/oauth/v2/auth?..." }
    ↓
App opens authUrl in browser
    ↓
User authorizes in Zoho
    ↓
Zoho redirects to: /api/zoho/callback?code=...&state=userId
    ↓
Backend exchanges code for tokens
    ↓
Tokens saved to database
    ↓
User returns to app
    ↓
App checks status: GET /api/zoho/status
    ↓
Status shows "Connected"
```

### Token Management

- **Access Token**: Expires in 1 hour, auto-refreshed when < 5 minutes remaining
- **Refresh Token**: Never expires (unless revoked)
- **Storage**: Tokens stored in `zoho_tokens` table per user

### Data Flow

```
Projects Screen
    ↓
User toggles Zoho projects ON
    ↓
App calls: GET /api/projects?includeZoho=true
    ↓
Backend:
  - Gets local projects from database
  - Gets Zoho projects via Zoho API
  - Combines both
    ↓
Returns: { local: [...], zoho: [...], all: [...] }
    ↓
App displays combined projects
```

## User Experience

### First Time Setup

1. User logs into the app
2. Navigates to Projects
3. Clicks Settings icon
4. Sees "Not Connected" status
5. Clicks "Connect Zoho Projects"
6. Browser opens for authorization
7. User authorizes
8. Returns to app
9. Status updates to "Connected"

### Daily Usage

1. User opens Projects screen
2. If Zoho is connected, cloud icon is visible
3. User clicks cloud icon to show Zoho projects
4. Both local and Zoho projects appear together
5. User can distinguish by color/badge

### Disconnecting

1. User goes to Zoho Integration screen
2. Clicks "Disconnect"
3. Confirms disconnection
4. Tokens removed from database
5. Status updates to "Not Connected"

## Error Handling

- **Connection Failed**: Shows error message, user can retry
- **Token Expired**: Automatically refreshed by backend
- **No Projects**: Shows empty state message
- **API Error**: Shows error snackbar with details

## Future Enhancements

- Auto-refresh projects periodically
- Sync local projects with Zoho
- Two-way sync capabilities
- Project filtering by source
- Search across both sources

