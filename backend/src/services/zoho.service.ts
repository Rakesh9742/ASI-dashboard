import axios, { AxiosInstance } from 'axios';
import { pool } from '../config/database';

interface ZohoTokenResponse {
  access_token?: string;
  refresh_token?: string;
  token_type?: string;
  expires_in?: number;
  scope?: string;
  error?: string;
  error_description?: string;
}

interface ZohoProject {
  id: string;
  name: string;
  description?: string;
  status?: string;
  start_date?: string;
  end_date?: string;
  owner_name?: string;
  created_time?: string;
  [key: string]: any;
}

interface ZohoProjectsResponse {
  projects: ZohoProject[];
  response: {
    result: {
      projects: ZohoProject[];
    };
  };
}

class ZohoService {
  private clientId: string;
  private clientSecret: string;
  private redirectUri: string;
  private apiUrl: string;
  private authUrl: string;

  constructor() {
    this.clientId = process.env.ZOHO_CLIENT_ID || '';
    this.clientSecret = process.env.ZOHO_CLIENT_SECRET || '';
    
    // Build redirect URI from BACKEND_URL if ZOHO_REDIRECT_URI is not set
    const backendUrl = process.env.BACKEND_URL || process.env.API_URL || 'http://localhost:3000';
    this.redirectUri = process.env.ZOHO_REDIRECT_URI || `${backendUrl}/api/zoho/callback`;
    
    // Zoho Projects API base URL - adjust based on your data center
    // US: https://projectsapi.zoho.com
    // EU: https://projectsapi.zoho.eu
    // IN: https://projectsapi.zoho.in
    // AU: https://projectsapi.zoho.com.au
    this.apiUrl = process.env.ZOHO_API_URL || 'https://projectsapi.zoho.com';
    this.authUrl = process.env.ZOHO_AUTH_URL || 'https://accounts.zoho.com';
    
    // Validate configuration
    if (!this.clientId) {
      console.error('⚠️  WARNING: ZOHO_CLIENT_ID is not set in environment variables');
    }
    if (!this.clientSecret) {
      console.error('⚠️  WARNING: ZOHO_CLIENT_SECRET is not set in environment variables');
    }
    if (!this.redirectUri) {
      console.error('⚠️  WARNING: ZOHO_REDIRECT_URI or BACKEND_URL is not set in environment variables');
    }
    
    // Log configuration for debugging (without sensitive data)
    console.log('Zoho Service Configuration:', {
      redirectUri: this.redirectUri,
      apiUrl: this.apiUrl,
      authUrl: this.authUrl,
      hasClientId: !!this.clientId,
      hasClientSecret: !!this.clientSecret
    });
  }

  /**
   * Get authorization URL for OAuth flow
   */
  getAuthorizationUrl(state?: string): string {
    // Request profile + email + projects + people scopes and force consent to obtain refresh_token
    // Zoho expects scopes space-separated
    // Note: Zoho People scopes must be UPPERCASE: ZOHOPEOPLE not ZohoPeople
    // For accessing employee forms, we need ZOHOPEOPLE.forms.ALL scope
    const scope = [
      'AaaServer.profile.read',
      'profile',
      'email',
      'ZohoProjects.projects.READ',
      'ZohoProjects.portals.READ',
      'ZohoProjects.tasks.READ',  // Required for reading tasks and subtasks
      'ZohoProjects.tasklists.READ',  // Required for reading tasklists
      'ZOHOPEOPLE.forms.ALL',  // Required for accessing employee forms/records
      'ZOHOPEOPLE.employee.ALL',  // Also include employee scope
    ].join(' ');

    const params = new URLSearchParams({
      client_id: this.clientId,
      redirect_uri: this.redirectUri,
      response_type: 'code',
      scope,
      access_type: 'offline',
      prompt: 'consent',
      ...(state && { state }),
    });

    return `${this.authUrl}/oauth/v2/auth?${params.toString()}`;
  }

  /**
   * Exchange authorization code for access token
   */
  async exchangeCodeForToken(code: string): Promise<ZohoTokenResponse> {
    // Validate configuration before making request
    if (!this.clientId || !this.clientSecret || !this.redirectUri) {
      throw new Error('Zoho OAuth configuration is incomplete. Please check ZOHO_CLIENT_ID, ZOHO_CLIENT_SECRET, and ZOHO_REDIRECT_URI environment variables.');
    }

    try {
      const tokenRequestParams = {
        client_id: this.clientId,
        client_secret: this.clientSecret,
        redirect_uri: this.redirectUri,
        code,
        grant_type: 'authorization_code',
      };

      // Log request details (without exposing secrets)
      console.log('Exchanging code for token:', {
        auth_url: `${this.authUrl}/oauth/v2/token`,
        client_id: this.clientId,
        redirect_uri: this.redirectUri,
        has_code: !!code,
        code_length: code?.length,
        grant_type: 'authorization_code'
      });

      let response;
      try {
        response = await axios.post(
          `${this.authUrl}/oauth/v2/token`,
          new URLSearchParams(tokenRequestParams),
          {
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
            },
          }
        );
      } catch (axiosError: any) {
        // If we get a response, log it for debugging
        if (axiosError.response) {
          console.error('Zoho API Error Details:', {
            status: axiosError.response.status,
            statusText: axiosError.response.statusText,
            data: axiosError.response.data,
            url: axiosError.config?.url,
            request_data: {
              client_id: this.clientId,
              redirect_uri: this.redirectUri,
              has_code: !!code
            }
          });
        }
        throw axiosError;
      }

      const tokenData = response.data;
      
      // Check for error in response
      if (tokenData.error) {
        const errorMsg = tokenData.error_description || 'No description provided';
        let detailedError = `Zoho OAuth error: ${tokenData.error} - ${errorMsg}`;
        
        // Provide helpful hints based on error type
        if (tokenData.error === 'invalid_client') {
          detailedError += '\n\n🔍 TROUBLESHOOTING STEPS:';
          detailedError += '\n\n1. CHECK DATA CENTER MATCH:';
          detailedError += '\n   - Your ZOHO_AUTH_URL is: ' + this.authUrl;
          detailedError += '\n   - Check your Zoho account data center:';
          detailedError += '\n     * Login to https://accounts.zoho.com and check URL after login';
          detailedError += '\n     * If URL contains .eu, use: https://accounts.zoho.eu';
          detailedError += '\n     * If URL contains .in, use: https://accounts.zoho.in';
          detailedError += '\n     * If URL contains .com.au, use: https://accounts.zoho.com.au';
          detailedError += '\n     * If URL is .com, use: https://accounts.zoho.com (current)';
          detailedError += '\n\n2. VERIFY REDIRECT URI:';
          detailedError += '\n   - Your redirect URI: ' + this.redirectUri;
          detailedError += '\n   - Must match EXACTLY in Zoho Developer Console';
          detailedError += '\n   - Check for trailing slashes, http vs https, etc.';
          detailedError += '\n   - Go to: https://api-console.zoho.com/ (or .eu/.in/.com.au)';
          detailedError += '\n\n3. VERIFY CLIENT CREDENTIALS:';
          detailedError += '\n   - Client ID: ' + this.clientId.substring(0, 20) + '...';
          detailedError += '\n   - Check for extra spaces/newlines in .env file';
          detailedError += '\n   - Regenerate client secret if needed';
          detailedError += '\n\n4. CHECK OAUTH APP STATUS:';
          detailedError += '\n   - Ensure app is "Active" in Zoho Developer Console';
          detailedError += '\n   - Verify app has correct scopes: ZohoProjects.projects.READ,ZohoProjects.portals.READ';
        } else if (tokenData.error === 'invalid_grant') {
          detailedError += '\n\nTroubleshooting tips:';
          detailedError += '\n1. Authorization code may have expired (codes are single-use and expire quickly)';
          detailedError += '\n2. Code may have already been used';
          detailedError += '\n3. Try getting a new authorization URL and code';
        }
        
        throw new Error(detailedError);
      }
      
      // Log the response structure for debugging
      console.log('Zoho token exchange response:', {
        has_access_token: !!tokenData.access_token,
        has_refresh_token: !!tokenData.refresh_token,
        expires_in: tokenData.expires_in,
        token_type: tokenData.token_type,
        error: tokenData.error,
        error_description: tokenData.error_description,
        keys: Object.keys(tokenData),
        full_response: JSON.stringify(tokenData, null, 2)
      });

      // Validate required fields
      if (!tokenData.access_token) {
        throw new Error(`Zoho token response missing access_token. Response: ${JSON.stringify(tokenData)}`);
      }

      if (!tokenData.refresh_token) {
        console.warn('Zoho token response missing refresh_token. This may cause issues with token refresh.');
      }

      return tokenData as ZohoTokenResponse;
    } catch (error: any) {
      // Enhanced error logging
      if (error.response) {
        console.error('Zoho API Error Response:', {
          status: error.response.status,
          statusText: error.response.statusText,
          data: error.response.data,
          headers: error.response.headers
        });
      } else {
        console.error('Error exchanging code for token:', error.message);
      }
      
      // Re-throw with more context if it's not already a detailed error
      if (error.message && error.message.includes('Zoho OAuth error')) {
        throw error;
      }
      
      throw new Error(`Failed to exchange code for token: ${error.response?.data?.error || error.response?.data?.error_description || error.message}`);
    }
  }

  /**
   * Refresh access token using refresh token
   */
  async refreshAccessToken(refreshToken: string): Promise<ZohoTokenResponse> {
    try {
      const response = await axios.post(
        `${this.authUrl}/oauth/v2/token`,
        new URLSearchParams({
          client_id: this.clientId,
          client_secret: this.clientSecret,
          refresh_token: refreshToken,
          grant_type: 'refresh_token',
        }),
        {
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        }
      );

      return response.data;
    } catch (error: any) {
      console.error('Error refreshing token:', error.response?.data || error.message);
      throw new Error(`Failed to refresh token: ${error.response?.data?.error || error.message}`);
    }
  }

  /**
   * Get or refresh access token for a user
   */
  async getValidAccessToken(userId: number): Promise<string> {
    const result = await pool.query(
      'SELECT access_token, refresh_token, expires_at FROM zoho_tokens WHERE user_id = $1',
      [userId]
    );

    if (result.rows.length === 0) {
      throw new Error('No Zoho token found for user. Please authorize first.');
    }

    const token = result.rows[0];
    const expiresAt = new Date(token.expires_at);
    const now = new Date();

    // If token expires in less than 5 minutes, refresh it
    if (expiresAt.getTime() - now.getTime() < 5 * 60 * 1000) {
      console.log('Token expiring soon, refreshing...');
      const newTokenData = await this.refreshAccessToken(token.refresh_token);
      
      // Validate access_token is present
      if (!newTokenData.access_token) {
        throw new Error('Failed to refresh token: access_token missing from response');
      }
      
      // Validate expires_in and provide default (3600 seconds = 1 hour)
      const expiresInNew = newTokenData.expires_in && typeof newTokenData.expires_in === 'number' && !isNaN(newTokenData.expires_in) && newTokenData.expires_in > 0
        ? newTokenData.expires_in
        : 3600;
      
      // Calculate expiration time more robustly
      const nowNew = Date.now();
      const expiresAtNew = new Date(nowNew + (expiresInNew * 1000));
      
      // Validate the date is valid
      if (isNaN(expiresAtNew.getTime())) {
        throw new Error(`Invalid expiration date calculated during refresh. expires_in: ${newTokenData.expires_in}`);
      }

      await pool.query(
        `UPDATE zoho_tokens 
         SET access_token = $1, 
             refresh_token = $2,
             expires_at = $3,
             updated_at = CURRENT_TIMESTAMP
         WHERE user_id = $4`,
        [newTokenData.access_token, newTokenData.refresh_token || token.refresh_token, expiresAtNew, userId]
      );

      return newTokenData.access_token;
    }

    return token.access_token;
  }

  /**
   * Create authenticated axios instance
   */
  private async getAuthenticatedClient(userId: number): Promise<AxiosInstance> {
    const accessToken = await this.getValidAccessToken(userId);

    return axios.create({
      baseURL: this.apiUrl,
      headers: {
        'Authorization': `Zoho-oauthtoken ${accessToken}`,
        'Content-Type': 'application/json',
      },
    });
  }

  /**
   * Get Zoho user information using access token
   */
  async getZohoUserInfo(accessToken: string): Promise<any> {
    try {
      // Try the user info endpoint first
      const response = await axios.get(
        `${this.authUrl}/oauth/user/info`,
        {
          headers: {
            'Authorization': `Zoho-oauthtoken ${accessToken}`,
            'Content-Type': 'application/json',
          },
        }
      );

      console.log('Zoho user info response:', JSON.stringify(response.data).substring(0, 300));
      return response.data;
    } catch (error: any) {
      console.error('Error fetching Zoho user info from oauth/user/info:', error.response?.data || error.message);
      
      // Try alternative: Get user info from Projects API
      try {
        const projectsResponse = await axios.get(
          `${this.apiUrl}/restapi/portals/`,
          {
            headers: {
              'Authorization': `Zoho-oauthtoken ${accessToken}`,
              'Content-Type': 'application/json',
            },
          }
        );
        
        // Extract user info from portals response
        const portals = projectsResponse.data?.portals || projectsResponse.data?.response?.result?.portals || [];
        if (portals.length > 0 && portals[0].portal_owner) {
          const owner = portals[0].portal_owner;
          return {
            email: owner.email,
            Email: owner.email,
            name: owner.name || owner.first_name,
            Name: owner.name || owner.first_name,
            first_name: owner.first_name,
            last_name: owner.last_name,
            display_name: `${owner.first_name || ''} ${owner.last_name || ''}`.trim() || owner.name,
            Display_Name: `${owner.first_name || ''} ${owner.last_name || ''}`.trim() || owner.name,
          };
        }
      } catch (projectsError: any) {
        console.error('Error fetching from Projects API:', projectsError.response?.data || projectsError.message);
      }
      
      // Last resort: Try CRM API
      // Use ZOHO_CRM_API_URL or derive from ZOHO_API_URL
      const crmApiUrl = process.env.ZOHO_CRM_API_URL || 
        (this.apiUrl.includes('.in') ? 'https://www.zohoapis.in' :
         this.apiUrl.includes('.eu') ? 'https://www.zohoapis.eu' :
         this.apiUrl.includes('.com.au') ? 'https://www.zohoapis.com.au' :
         'https://www.zohoapis.com');
      
      try {
        const crmResponse = await axios.get(
          `${crmApiUrl}/crm/v2/users`,
          {
            headers: {
              'Authorization': `Zoho-oauthtoken ${accessToken}`,
              'Content-Type': 'application/json',
            },
          }
        );
        const user = crmResponse.data?.users?.[0];
        if (user) {
          return {
            email: user.email || user.Email,
            Email: user.email || user.Email,
            name: user.full_name || user.Full_Name || user.name || user.Name,
            Name: user.full_name || user.Full_Name || user.name || user.Name,
            display_name: user.full_name || user.Full_Name,
            Display_Name: user.full_name || user.Full_Name,
          };
        }
      } catch (crmError: any) {
        console.error('Error fetching from CRM API:', crmError.response?.data || crmError.message);
      }
      
      // If all fail, throw error with helpful message
      throw new Error(`Failed to fetch Zoho user info. Please ensure your Zoho account has an email address. Original error: ${error.message}`);
    }
  }

  /**
   * Get Zoho People record by email
   */
  async getZohoPeopleRecord(accessToken: string, email: string): Promise<any> {
    // Zoho People API base URL - use people.zoho.{dc} format
    const peopleBase = this.authUrl.replace('accounts.zoho', 'people.zoho');
    // Correct People API endpoint format
    const url = `${peopleBase}/people/api/forms/P_EmployeeView/records?searchColumn=Email&searchValue=${encodeURIComponent(email)}`;

    try {
      const response = await axios.get(url, {
        headers: {
          'Authorization': `Zoho-oauthtoken ${accessToken}`,
          'Content-Type': 'application/json',
        },
      });

      console.log('Zoho People API response structure:', {
        hasResponse: !!response.data?.response,
        hasResult: !!response.data?.response?.result,
        keys: Object.keys(response.data || {}),
        status: response.status,
        dataType: Array.isArray(response.data) ? 'Array' : typeof response.data,
        firstKey: Object.keys(response.data || {})[0]
      });

      // Zoho People returns data in different shapes; normalize
      let records: any[] = [];
      let singleRecord: any = null;
      
      // Check if response.data is directly an array (like { '0': {...} } or [{...}])
      if (Array.isArray(response.data)) {
        records = response.data;
        console.log('Response is direct array, length:', records.length);
      }
      // Check if response.data is an object with numeric keys (like { '0': {...}, '1': {...} })
      else if (response.data && typeof response.data === 'object') {
        const keys = Object.keys(response.data);
        // If keys are numeric strings, it's likely an array-like object
        if (keys.length > 0 && /^\d+$/.test(keys[0])) {
          records = keys.map(key => response.data[key]).filter(Boolean);
          console.log('Response is array-like object, converted to array, length:', records.length);
        }
        // Check nested structures
        else if (response.data?.response?.result) {
          if (Array.isArray(response.data.response.result)) {
            records = response.data.response.result;
            console.log('Found array in response.response.result');
          } else if (response.data.response.result?.records && Array.isArray(response.data.response.result.records)) {
            records = response.data.response.result.records;
            console.log('Found array in response.response.result.records');
          } else if (response.data.response.result && typeof response.data.response.result === 'object') {
            singleRecord = response.data.response.result;
            console.log('Found single record in response.response.result');
          }
        } else if (response.data?.records && Array.isArray(response.data.records)) {
          records = response.data.records;
          console.log('Found array in response.records');
        } else if (response.data?.data && Array.isArray(response.data.data)) {
          records = response.data.data;
          console.log('Found array in response.data');
        } else {
          // Single record object
          singleRecord = response.data;
          console.log('Response is single record object');
        }
      }
      
      if (singleRecord) {
        console.log('Returning single record, keys:', Object.keys(singleRecord));
        return singleRecord;
      }
      
      console.log('Zoho People records found:', records.length);
      if (records.length > 0) {
        console.log('First record keys:', Object.keys(records[0]));
        console.log('First record sample:', JSON.stringify(records[0]).substring(0, 200));
        return records[0];
      }
      
      console.log('No records found in Zoho People response');
      return {};
    } catch (error: any) {
      console.error('Error fetching Zoho People record:', {
        url,
        status: error.response?.status,
        data: error.response?.data,
        message: error.message
      });
      return {};
    }
  }

  /**
   * Get list of employees from Zoho People (basic fetch)
   */
  async getZohoPeopleEmployees(accessToken: string, page: number = 1, perPage: number = 200): Promise<any[]> {
    // Zoho People API base URL - use people.zoho.{dc} format
    const peopleBase = this.authUrl.replace('accounts.zoho', 'people.zoho');
    // Correct People API endpoint format
    const url = `${peopleBase}/people/api/forms/P_EmployeeView/records?page=${page}&perPage=${perPage}`;

    try {
      const response = await axios.get(url, {
        headers: {
          'Authorization': `Zoho-oauthtoken ${accessToken}`,
          'Content-Type': 'application/json',
        },
      });

      console.log('Zoho People employees API response:', {
        status: response.status,
        hasResponse: !!response.data?.response,
        hasResult: !!response.data?.response?.result,
        keys: Object.keys(response.data || {}),
        recordCount: Array.isArray(response.data?.response?.result) ? response.data.response.result.length : 0
      });

      // Zoho People returns data in different shapes; normalize
      const records = response.data?.response?.result || 
                     response.data?.response?.result?.records ||
                     response.data?.records || 
                     response.data?.data || [];
      if (Array.isArray(records)) {
        return records;
      }
      return [];
    } catch (error: any) {
      console.error('Error fetching Zoho People employees:', {
        url,
        status: error.response?.status,
        data: error.response?.data,
        message: error.message
      });
      throw new Error(`Failed to fetch employees from Zoho People: ${error.response?.data?.errors?.message || error.message}`);
    }
  }

  /**
   * Get all portals (workspaces) for the user
   */
  async getPortals(userId: number): Promise<any[]> {
    try {
      const client = await this.getAuthenticatedClient(userId);
      const response = await client.get('/restapi/portals/');

      // Zoho API response structure may vary
      if (response.data.response?.result?.portals) {
        return response.data.response.result.portals;
      }
      return response.data.portals || [];
    } catch (error: any) {
      console.error('Error fetching portals:', error.response?.data || error.message);
      throw new Error(`Failed to fetch portals: ${error.response?.data?.error || error.message}`);
    }
  }

  /**
   * Get all projects from Zoho Projects
   */
  async getProjects(userId: number, portalId?: string): Promise<ZohoProject[]> {
    try {
      const client = await this.getAuthenticatedClient(userId);
      
      // If portalId is provided, use it; otherwise get first portal
      let portal = portalId;
      if (!portal) {
        const portals = await this.getPortals(userId);
        if (portals.length === 0) {
          throw new Error('No portals found. Please create a portal in Zoho Projects first.');
        }
        portal = portals[0].id;
      }

      // Use singular "portal" not plural "portals" - based on Zoho API format
      const response = await client.get(`/restapi/portal/${portal}/projects/`);

      // Handle different response structures
      let projects: ZohoProject[] = [];
      
      if (response.data.response?.result?.projects) {
        projects = response.data.response.result.projects;
      } else if (response.data.projects) {
        projects = response.data.projects;
      } else if (Array.isArray(response.data)) {
        projects = response.data;
      }

      return projects;
    } catch (error: any) {
      console.error('Error fetching projects:', error.response?.data || error.message);
      throw new Error(`Failed to fetch projects: ${error.response?.data?.error?.message || error.message}`);
    }
  }

  /**
   * Get single project details
   */
  async getProject(userId: number, projectId: string, portalId?: string): Promise<ZohoProject> {
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

      // Use singular "portal" not plural "portals" - based on Zoho API format
      const response = await client.get(`/restapi/portal/${portal}/projects/${projectId}/`);

      if (response.data.response?.result) {
        return response.data.response.result;
      }
      return response.data;
    } catch (error: any) {
      console.error('Error fetching project:', error.response?.data || error.message);
      throw new Error(`Failed to fetch project: ${error.response?.data?.error?.message || error.message}`);
    }
  }

  /**
   * Get tasks for a project
   * Zoho Projects organizes tasks under tasklists, so we need to:
   * 1. Get all tasklists for the project
   * 2. Get tasks from each tasklist
   * 3. Get subtasks for each task
   */
  async getTasks(userId: number, projectId: string, portalId?: string): Promise<any[]> {
    try {
      const client = await this.getAuthenticatedClient(userId);
      
      let portal = portalId;
      let portalName: string | undefined;
      if (!portal) {
        const portals = await this.getPortals(userId);
        if (portals.length === 0) {
          throw new Error('No portals found.');
        }
        portal = portals[0].id;
        portalName = portals[0].name || portals[0].portal_name || portals[0].id_string;
        console.log('Portal details:', {
          id: portal,
          name: portalName,
          allKeys: Object.keys(portals[0])
        });
      } else {
        // If portal ID provided, try to get portal name
        try {
          const portals = await this.getPortals(userId);
          const matchingPortal = portals.find(p => p.id === portal || p.id_string === portal);
          if (matchingPortal) {
            portalName = matchingPortal.name || matchingPortal.portal_name || matchingPortal.id_string;
          }
        } catch (e) {
          // Ignore if we can't get portal name
        }
      }

      console.log('Using portal:', { id: portal, name: portalName });

      // Zoho Projects organizes tasks under tasklists
      // We need to get tasklists first, then tasks from each tasklist
      let allTasks: any[] = [];
      let correctProjectId = projectId; // Will be updated when we get the project
      
      try {
        // First, try to get the project to see if it has task links or tasklist info
        // Try multiple endpoint formats since single project endpoint might use different format
        console.log('Fetching project details...');
        let projectResponse;
        let project;
        
        // Try different endpoint formats for getting project
        const projectEndpointVariations = [];
        
        // Try with portal name if available
        if (portalName) {
          projectEndpointVariations.push({
            name: 'portal name',
            url: `/restapi/portal/${portalName}/projects/${projectId}/`
          });
        }
        
        // Try with portal ID
        projectEndpointVariations.push({
          name: 'portal ID',
          url: `/restapi/portal/${portal}/projects/${projectId}/`
        });
        
        // Try without /restapi/ prefix
        if (portalName) {
          projectEndpointVariations.push({
            name: 'portal name without /restapi/',
            url: `/portal/${portalName}/projects/${projectId}/`
          });
        }
        projectEndpointVariations.push({
          name: 'portal ID without /restapi/',
          url: `/portal/${portal}/projects/${projectId}/`
        });
        
        let projectFetchSuccess = false;
        for (const variation of projectEndpointVariations) {
          try {
            console.log(`Trying project endpoint: ${variation.name} - ${variation.url}`);
            projectResponse = await client.get(variation.url);
            project = projectResponse.data.response?.result || projectResponse.data;
            console.log('✅ Project fetched successfully via', variation.name);
            projectFetchSuccess = true;
            break;
          } catch (projectError: any) {
            console.log(`❌ Project endpoint ${variation.name} failed:`, projectError.response?.data?.error?.message || projectError.message);
            // Continue to next variation
          }
        }
        
        // If all project endpoints failed, try getting from projects list
        if (!projectFetchSuccess) {
          console.log('⚠️  Single project endpoint failed, trying to get from projects list...');
          try {
            const projectsResponse = await client.get(`/restapi/portal/${portal}/projects/`);
            let projects: any[] = [];
            
            if (projectsResponse.data.response?.result?.projects) {
              projects = projectsResponse.data.response.result.projects;
            } else if (projectsResponse.data.projects) {
              projects = projectsResponse.data.projects;
            } else if (Array.isArray(projectsResponse.data)) {
              projects = projectsResponse.data;
            }
            
            // Find the project by ID
            project = projects.find((p: any) => 
              p.id === projectId || 
              p.id_string === projectId || 
              p.id?.toString() === projectId.toString()
            );
            
            if (project) {
              console.log('✅ Found project in projects list');
              projectFetchSuccess = true;
            } else {
              console.error('❌ Project not found in projects list. Available project IDs:', projects.map((p: any) => p.id || p.id_string));
            }
          } catch (listError: any) {
            console.error('❌ Failed to get projects list:', listError.response?.data?.error?.message || listError.message);
          }
        }
        
        if (!projectFetchSuccess || !project) {
          console.error('❌ Could not fetch project data. Cannot proceed with task fetching.');
          // Don't throw - return empty array so UI can still show project info
          return [];
        }
        
        console.log('=== PROJECT DATA INSPECTION ===');
        console.log('Project data keys:', Object.keys(project || {}));
        console.log('Total number of fields:', Object.keys(project || {}).length);
        console.log('Project ID:', projectId);
        console.log('Portal ID:', portal);
        console.log('Portal Name:', portalName);
        
        // Log ALL project fields and their values (for debugging)
        if (project) {
          console.log('\n--- ALL PROJECT FIELDS ---');
          Object.keys(project).forEach(key => {
            const value = project[key];
            let displayValue = value;
            if (value === null || value === undefined) {
              displayValue = 'null/undefined';
            } else if (typeof value === 'object') {
              if (Array.isArray(value)) {
                displayValue = `[Array with ${value.length} items]`;
              } else {
                displayValue = `{Object with keys: ${Object.keys(value).join(', ')}` + (Object.keys(value).length > 10 ? '...' : '') + '}';
              }
            } else if (typeof value === 'string' && value.length > 100) {
              displayValue = value.substring(0, 100) + '...';
            }
            console.log(`  ${key}: ${displayValue}`);
          });
          console.log('--- END ALL PROJECT FIELDS ---\n');
          
          // Check if project has any task-related fields
          const taskRelatedKeys = Object.keys(project).filter(key => 
            key.toLowerCase().includes('task') || 
            key.toLowerCase().includes('milestone') ||
            key.toLowerCase().includes('list')
          );
          console.log('Task-related keys in project:', taskRelatedKeys);
          
          // Log important project fields
          console.log('\n--- IMPORTANT PROJECT FIELDS ---');
          console.log('  id:', project.id);
          console.log('  id_string:', project.id_string);
          console.log('  name:', project.name);
          console.log('  link:', project.link);
          console.log('  url:', project.url);
          console.log('  portal_id:', project.portal_id);
          console.log('  owner_id:', project.owner_id);
          console.log('  owner_name:', project.owner_name);
          console.log('  status:', project.status);
          console.log('  description:', project.description?.substring(0, 100) || 'N/A');
          console.log('--- END IMPORTANT FIELDS ---\n');
        } else {
          console.error('❌ Project object is null or undefined!');
        }
        console.log('=== END PROJECT DATA INSPECTION ===');
        
        // Use the correct project ID - prefer id_string over id (as seen in link URLs)
        correctProjectId = project?.id_string || projectId;
        console.log(`🔑 Using project ID: ${correctProjectId} (original: ${projectId}, id_string: ${project?.id_string})`);
        
        // Try different endpoint variations for tasklists
        // Based on Zoho Projects API, try multiple formats
        const endpointVariations = [];
        
        // 0. FIRST: Try using the link URL from project object (this is the correct one!)
        if (project?.link?.tasklist?.url) {
          const tasklistUrl = project.link.tasklist.url;
          const tasklistPath = tasklistUrl.replace('https://projectsapi.zoho.in', '');
          endpointVariations.push({
            name: 'project.link.tasklist URL (CORRECT)',
            url: tasklistPath
          });
        }
        
        // 1. Try with id_string (the correct project ID)
        if (correctProjectId !== projectId) {
          endpointVariations.push({
            name: 'portal ID with id_string',
            url: `/restapi/portal/${portal}/projects/${correctProjectId}/tasklists/`
          });
        }
        
        // 2. Try with portal name (as seen in web URL: portal/sumedhadesignsystemspvtltd231)
        if (portalName) {
          endpointVariations.push({
            name: 'portal name with /restapi/',
            url: `/restapi/portal/${portalName}/projects/${correctProjectId}/tasklists/`
          });
          endpointVariations.push({
            name: 'portal name without /restapi/',
            url: `/portal/${portalName}/projects/${correctProjectId}/tasklists/`
          });
        }
        
        // 3. Try with portal ID (standard REST API format) using id_string
        endpointVariations.push({
          name: 'portal ID with /restapi/ (id_string)',
          url: `/restapi/portal/${portal}/projects/${correctProjectId}/tasklists/`
        });
        endpointVariations.push({
          name: 'portal ID without /restapi/ (id_string)',
          url: `/portal/${portal}/projects/${correctProjectId}/tasklists/`
        });
        
        // 4. Try with original projectId as fallback
        endpointVariations.push({
          name: 'portal ID with /restapi/ (original id)',
          url: `/restapi/portal/${portal}/projects/${projectId}/tasklists/`
        });
        
        // 5. Try with API versions using id_string
        endpointVariations.push({
          name: 'v3 API with portal ID (id_string)',
          url: `/restapi/v3/portal/${portal}/projects/${correctProjectId}/tasklists/`
        });
        endpointVariations.push({
          name: 'v1 API with portal ID (id_string)',
          url: `/restapi/v1/portal/${portal}/projects/${correctProjectId}/tasklists/`
        });
        
        let tasklists: any[] = [];
        let tasklistsResponse;
        
        for (const variation of endpointVariations) {
          if (tasklists.length > 0) break; // Stop if we found tasklists
          
          try {
            console.log(`Trying tasklists endpoint: ${variation.name} - ${variation.url}`);
            tasklistsResponse = await client.get(variation.url);
            
            if (tasklistsResponse.data.response?.result?.tasklists) {
              tasklists = tasklistsResponse.data.response.result.tasklists;
            } else if (tasklistsResponse.data.tasklists) {
              tasklists = tasklistsResponse.data.tasklists;
            } else if (Array.isArray(tasklistsResponse.data)) {
              tasklists = tasklistsResponse.data;
            } else if (tasklistsResponse.data.response?.result && Array.isArray(tasklistsResponse.data.response.result)) {
              tasklists = tasklistsResponse.data.response.result;
            }
            
            if (tasklists.length > 0) {
              console.log(`✅ Found ${tasklists.length} tasklists via ${variation.name}`);
              break;
            }
          } catch (error: any) {
            console.log(`❌ ${variation.name} failed:`, error.response?.data?.error?.message || error.message);
            // Continue to next variation
          }
        }
        
        // If still no tasklists found, try using the link URLs from project object
        if (tasklists.length === 0 && project?.link) {
          console.log('💡 Trying to use link URLs from project object...');
          
          // Use the tasklist URL from project.link if available
          if (project.link.tasklist?.url) {
            try {
              // Extract the path from the full URL
              const tasklistUrl = project.link.tasklist.url;
              // Remove the base URL to get just the path
              const tasklistPath = tasklistUrl.replace('https://projectsapi.zoho.in', '');
              console.log(`Trying tasklist URL from project.link: ${tasklistPath}`);
              
              tasklistsResponse = await client.get(tasklistPath);
              
              if (tasklistsResponse.data.response?.result?.tasklists) {
                tasklists = tasklistsResponse.data.response.result.tasklists;
              } else if (tasklistsResponse.data.tasklists) {
                tasklists = tasklistsResponse.data.tasklists;
              } else if (Array.isArray(tasklistsResponse.data)) {
                tasklists = tasklistsResponse.data;
              } else if (tasklistsResponse.data.response?.result && Array.isArray(tasklistsResponse.data.response.result)) {
                tasklists = tasklistsResponse.data.response.result;
              }
              
              if (tasklists.length > 0) {
                console.log(`✅ Found ${tasklists.length} tasklists using project.link.tasklist URL!`);
              }
            } catch (linkError: any) {
              console.log(`❌ project.link.tasklist URL failed:`, linkError.response?.data?.error?.message || linkError.message);
            }
          }
        }
        
        // If still no tasklists found after trying all variations
        if (tasklists.length === 0) {
          console.error('=== ALL TASKLIST ENDPOINT VARIATIONS FAILED ===');
          console.error('Tried all endpoint variations but none worked');
          console.error('Portal ID:', portal);
          console.error('Portal Name:', portalName);
          console.error('Project ID (id):', projectId);
          console.error('Project ID (id_string):', project?.id_string);
          console.error('Project link.tasklist URL:', project?.link?.tasklist?.url);
          console.error('');
          console.error('⚠️  ROOT CAUSE ANALYSIS:');
          console.error('The Zoho Projects REST API may not expose tasks/tasklists through these endpoints.');
          console.error('Possible reasons:');
          console.error('1. Tasks API might require different endpoint structure');
          console.error('2. Tasks might be accessed through milestones or different resource');
          console.error('3. API version mismatch - tasks might be in a different API version');
          console.error('4. Additional permissions or different authentication required');
          console.error('5. Tasks might only be accessible through Zoho Projects web interface, not REST API');
          console.error('');
          console.error('💡 SUGGESTION: Check Zoho Projects API documentation for correct tasks endpoint format');
          console.error('=== END TASKLIST FAILURE ===');
          // Will fall through to try direct tasks endpoint
        }
        
        console.log(`Found ${tasklists.length} tasklists for project ${projectId}`);
        
        // Get tasks from each tasklist
        for (const tasklist of tasklists) {
          const tasklistId = tasklist.id_string || tasklist.id;
          const tasklistName = tasklist.name || tasklist.tasklist_name || 'Unnamed Tasklist';
          
          if (!tasklistId) {
            console.warn('Tasklist missing ID, skipping:', tasklist);
            continue;
          }
          
          try {
            // Try different endpoint formats
            let tasksResponse;
            let tasks: any[] = [];
            
            // Try different endpoint formats for tasks
            // Use correctProjectId (id_string) instead of projectId
            // Add query parameters to get all task details
            try {
              // Try with correctProjectId first (the correct one) - request all fields
              try {
                tasksResponse = await client.get(
                  `/restapi/portal/${portal}/projects/${correctProjectId}/tasklists/${tasklistId}/tasks/?fields=all`
                );
              } catch (defaultError: any) {
                // Try without fields parameter
                try {
                  tasksResponse = await client.get(
                    `/restapi/portal/${portal}/projects/${correctProjectId}/tasklists/${tasklistId}/tasks/`
                  );
                } catch (noFieldsError: any) {
                  // Try v3 API with correctProjectId
                  try {
                    tasksResponse = await client.get(
                      `/restapi/v3/portal/${portal}/projects/${correctProjectId}/tasklists/${tasklistId}/tasks/?fields=all`
                    );
                  } catch (v3Error: any) {
                    try {
                      tasksResponse = await client.get(
                        `/restapi/v3/portal/${portal}/projects/${correctProjectId}/tasklists/${tasklistId}/tasks/`
                      );
                    } catch (v3NoFieldsError: any) {
                      // Try v1 API with correctProjectId
                      try {
                        tasksResponse = await client.get(
                          `/restapi/v1/portal/${portal}/projects/${correctProjectId}/tasklists/${tasklistId}/tasks/?fields=all`
                        );
                      } catch (v1Error: any) {
                        try {
                          tasksResponse = await client.get(
                            `/restapi/v1/portal/${portal}/projects/${correctProjectId}/tasklists/${tasklistId}/tasks/`
                          );
                        } catch (v1NoFieldsError: any) {
                          // Last resort: try with original projectId
                          tasksResponse = await client.get(
                            `/restapi/portal/${portal}/projects/${projectId}/tasklists/${tasklistId}/tasks/`
                          );
                        }
                      }
                    }
                  }
                }
              }
              
              if (tasksResponse.data.response?.result?.tasks) {
                tasks = tasksResponse.data.response.result.tasks;
              } else if (tasksResponse.data.tasks) {
                tasks = tasksResponse.data.tasks;
              } else if (Array.isArray(tasksResponse.data)) {
                tasks = tasksResponse.data;
              } else if (tasksResponse.data.response?.result && Array.isArray(tasksResponse.data.response.result)) {
                tasks = tasksResponse.data.response.result;
              }
            } catch (tasklistTasksError: any) {
              // If tasklist-specific endpoint fails, try getting all tasks with filter
              console.log(`Tasklist-specific endpoint failed for ${tasklistId}, trying alternative:`, tasklistTasksError.response?.data?.error?.message || tasklistTasksError.message);
              
              try {
                // Try getting all tasks and filter by tasklist - use correctProjectId
                let allTasksResponse;
                try {
                  allTasksResponse = await client.get(
                    `/restapi/portal/${portal}/projects/${correctProjectId}/tasks/?tasklist_id=${tasklistId}`
                  );
                } catch (defaultError: any) {
                  try {
                    allTasksResponse = await client.get(
                      `/restapi/v3/portal/${portal}/projects/${correctProjectId}/tasks/?tasklist_id=${tasklistId}`
                    );
                  } catch (v3Error: any) {
                    try {
                      allTasksResponse = await client.get(
                        `/restapi/v1/portal/${portal}/projects/${correctProjectId}/tasks/?tasklist_id=${tasklistId}`
                      );
                    } catch (v1Error: any) {
                      // Last resort: try with original projectId
                      allTasksResponse = await client.get(
                        `/restapi/portal/${portal}/projects/${projectId}/tasks/?tasklist_id=${tasklistId}`
                      );
                    }
                  }
                }
                
                if (allTasksResponse.data.response?.result?.tasks) {
                  tasks = allTasksResponse.data.response.result.tasks;
                } else if (allTasksResponse.data.tasks) {
                  tasks = allTasksResponse.data.tasks;
                } else if (Array.isArray(allTasksResponse.data)) {
                  tasks = allTasksResponse.data;
                }
              } catch (allTasksError: any) {
                console.warn(`Failed to fetch tasks for tasklist ${tasklistId} (${tasklistName}):`, allTasksError.response?.data?.error?.message || allTasksError.message);
                // Continue to next tasklist
                continue;
              }
            }
            
            console.log(`Found ${tasks.length} tasks in tasklist "${tasklistName}" (ID: ${tasklistId})`);
            
            // Log task details for debugging
            if (tasks.length > 0) {
              console.log(`📋 Sample task from "${tasklistName}":`, JSON.stringify(tasks[0], null, 2).substring(0, 500));
              // Log all task names to see what we got
              const taskNames = tasks.map(t => t.name || t.task_name || 'Unnamed').join(', ');
              console.log(`📋 Task names in "${tasklistName}": ${taskNames}`);
            }
            
            // Add tasklist info to each task
            tasks = tasks.map(task => ({
              ...task,
              tasklist_id: tasklistId,
              tasklist_name: tasklistName
            }));
            
            allTasks = allTasks.concat(tasks);
          } catch (tasklistError: any) {
            console.warn(`Failed to fetch tasks from tasklist ${tasklistId} (${tasklistName}):`, tasklistError.response?.data?.error?.message || tasklistError.message);
            // Continue to next tasklist instead of failing completely
          }
        }
        
        // If no tasks found through tasklists, try direct tasks endpoint as fallback
        if (allTasks.length === 0) {
          console.log('No tasks found through tasklists, trying direct tasks endpoint...');
          try {
            // Try different API versions for direct tasks
            let directTasksResponse;
            try {
              // Try without /restapi/ prefix first
              directTasksResponse = await client.get(`/portal/${portal}/projects/${projectId}/tasks/`);
            } catch (noRestApiError: any) {
              try {
                directTasksResponse = await client.get(`/restapi/v3/portal/${portal}/projects/${projectId}/tasks/`);
              } catch (v3Error: any) {
                try {
                  directTasksResponse = await client.get(`/restapi/v1/portal/${portal}/projects/${projectId}/tasks/`);
                } catch (v1Error: any) {
                  directTasksResponse = await client.get(`/restapi/portal/${portal}/projects/${projectId}/tasks/`);
                }
              }
            }
            
            if (directTasksResponse.data.response?.result?.tasks) {
              allTasks = directTasksResponse.data.response.result.tasks;
            } else if (directTasksResponse.data.tasks) {
              allTasks = directTasksResponse.data.tasks;
            } else if (Array.isArray(directTasksResponse.data)) {
              allTasks = directTasksResponse.data;
            } else if (directTasksResponse.data.response?.result && Array.isArray(directTasksResponse.data.response.result)) {
              allTasks = directTasksResponse.data.response.result;
            }
            
            console.log(`Found ${allTasks.length} tasks via direct endpoint`);
          } catch (directError: any) {
            console.error('=== DIRECT TASKS ENDPOINT FAILURE DETAILS ===');
            console.error('Error message:', directError.message);
            console.error('Status:', directError.response?.status);
            console.error('Status Text:', directError.response?.statusText);
            console.error('Error data:', JSON.stringify(directError.response?.data, null, 2));
            console.error('Request URL:', directError.config?.url);
            console.error('Base URL:', directError.config?.baseURL);
            console.error('=== END DIRECT TASKS ERROR DETAILS ===');
          }
        }
      } catch (tasklistsError: any) {
        console.error('=== TASKLISTS ERROR (CATCH BLOCK) ===');
        console.error('Error message:', tasklistsError.message);
        console.error('Status:', tasklistsError.response?.status);
        console.error('Error data:', JSON.stringify(tasklistsError.response?.data, null, 2));
        console.error('=== END TASKLISTS ERROR ===');
        // Try direct tasks endpoint as last resort with different API versions
        try {
          console.log('Trying direct tasks endpoint as fallback...');
          let directTasksResponse;
          try {
            // Try without /restapi/ prefix first
            directTasksResponse = await client.get(`/portal/${portal}/projects/${projectId}/tasks/`);
          } catch (noRestApiError: any) {
            try {
              directTasksResponse = await client.get(`/restapi/v3/portal/${portal}/projects/${projectId}/tasks/`);
            } catch (v3Error: any) {
              try {
                directTasksResponse = await client.get(`/restapi/v1/portal/${portal}/projects/${projectId}/tasks/`);
              } catch (v1Error: any) {
                directTasksResponse = await client.get(`/restapi/portal/${portal}/projects/${projectId}/tasks/`);
              }
            }
          }
          
          if (directTasksResponse.data.response?.result?.tasks) {
            allTasks = directTasksResponse.data.response.result.tasks;
          } else if (directTasksResponse.data.tasks) {
            allTasks = directTasksResponse.data.tasks;
          } else if (Array.isArray(directTasksResponse.data)) {
            allTasks = directTasksResponse.data;
          }
          
          console.log(`Found ${allTasks.length} tasks via fallback direct endpoint`);
        } catch (directError: any) {
          console.error('=== FINAL FALLBACK TASKS ENDPOINT FAILURE ===');
          console.error('Error message:', directError.message);
          console.error('Status:', directError.response?.status);
          console.error('Status Text:', directError.response?.statusText);
          console.error('Error data:', JSON.stringify(directError.response?.data, null, 2));
          console.error('Request URL:', directError.config?.url);
          console.error('Base URL:', directError.config?.baseURL);
          console.error('All task fetching methods failed');
          console.error('=== END FINAL FALLBACK ERROR ===');
          // Don't throw error - return empty array so UI can show "No tasks found" instead of error
          return [];
        }
      }

      // If no tasks found, return empty array
      if (allTasks.length === 0) {
        return [];
      }

      // Recursively fetch subtasks for each task
      // Use correctProjectId (id_string) instead of projectId
      // Note: correctProjectId was defined earlier in the try block, but we need to recalculate it here
      // since project might not be in scope. We'll use the same logic.
      // Get project again if needed, or use the correctProjectId that was calculated earlier
      // For now, we'll try to get it from the first task's context or recalculate
      let correctProjectIdForSubtasks = projectId;
      
      // Try to get id_string from the first task if available (tasks might have project_id_string)
      if (allTasks.length > 0 && allTasks[0].project_id_string) {
        correctProjectIdForSubtasks = allTasks[0].project_id_string;
      } else {
        // Fallback: try to get project again or use a pattern
        // Since we successfully fetched tasks using correctProjectId, we know it exists
        // We'll try both id_string pattern and original projectId
        correctProjectIdForSubtasks = projectId;
      }
      console.log(`\n🔄 Starting to fetch subtasks for ${allTasks.length} tasks...`);
      
      const tasksWithSubtasks = await Promise.all(
        allTasks.map(async (task) => {
          try {
            const taskId = task.id_string || task.id;
            const taskName = task.name || task.task_name || 'Unnamed Task';
            if (!taskId) {
              console.warn(`⚠️ Task has no ID, skipping subtask fetch:`, taskName);
              return { ...task, subtasks: [] };
            }
            
            // Try different endpoint formats for subtasks
            let subtasks: any[] = [];
            let subtasksResponse;
            
            // First, try using correctProjectId (id_string) - request all fields
            try {
              // Try with fields=all parameter first
              try {
                subtasksResponse = await client.get(
                  `/restapi/portal/${portal}/projects/${correctProjectId}/tasks/${taskId}/subtasks/?fields=all`
                );
              } catch (fieldsError: any) {
                // Try without fields parameter
                subtasksResponse = await client.get(
                  `/restapi/portal/${portal}/projects/${correctProjectId}/tasks/${taskId}/subtasks/`
                );
              }
              
              // Check multiple possible response structures
              if (subtasksResponse.data.response?.result?.subtasks) {
                subtasks = subtasksResponse.data.response.result.subtasks;
              } else if (subtasksResponse.data.response?.result?.tasks) {
                // Sometimes subtasks are returned as "tasks" in the result
                subtasks = subtasksResponse.data.response.result.tasks;
              } else if (subtasksResponse.data.subtasks) {
                subtasks = subtasksResponse.data.subtasks;
              } else if (subtasksResponse.data.tasks) {
                // Sometimes subtasks are returned as "tasks" at root level
                subtasks = subtasksResponse.data.tasks;
              } else if (Array.isArray(subtasksResponse.data)) {
                subtasks = subtasksResponse.data;
              } else if (subtasksResponse.data.response?.result && Array.isArray(subtasksResponse.data.response.result)) {
                subtasks = subtasksResponse.data.response.result;
              }
              
              if (subtasks.length > 0) {
                console.log(`✅ Found ${subtasks.length} subtasks for task ${taskId} (${task.name || task.task_name || 'Unnamed'}) using correctProjectId`);
                // Log sample subtask data
                console.log(`📋 Sample subtask data:`, JSON.stringify(subtasks[0], null, 2).substring(0, 300));
              } else {
                console.log(`ℹ️ No subtasks found for task ${taskId} (${task.name || task.task_name || 'Unnamed'})`);
                // Log the full response structure to debug
                if (subtasksResponse?.data) {
                  console.log(`📋 Subtask response keys:`, Object.keys(subtasksResponse.data));
                  if (subtasksResponse.data.response) {
                    console.log(`📋 Response.result keys:`, subtasksResponse.data.response.result ? Object.keys(subtasksResponse.data.response.result) : 'result is null');
                  }
                  // Log a sample of the actual response
                  console.log(`📋 Sample response:`, JSON.stringify(subtasksResponse.data, null, 2).substring(0, 500));
                }
              }
            } catch (correctIdError: any) {
              console.log(`⚠️ Subtask fetch failed for task ${taskId} (${task.name || task.task_name || 'Unnamed'}):`, 
                         correctIdError.response?.data?.error?.message || correctIdError.message);
              console.log(`   Attempted URL: /restapi/portal/${portal}/projects/${correctProjectId}/tasks/${taskId}/subtasks/`);
              // If that fails, try with original projectId
              try {
                subtasksResponse = await client.get(
                  `/restapi/portal/${portal}/projects/${projectId}/tasks/${taskId}/subtasks/`
                );
                
                if (subtasksResponse.data.response?.result?.subtasks) {
                  subtasks = subtasksResponse.data.response.result.subtasks;
                } else if (subtasksResponse.data.subtasks) {
                  subtasks = subtasksResponse.data.subtasks;
                } else if (Array.isArray(subtasksResponse.data)) {
                  subtasks = subtasksResponse.data;
                }
                
                if (subtasks.length > 0) {
                  console.log(`✅ Found ${subtasks.length} subtasks for task ${taskId} using original projectId`);
                }
              } catch (originalIdError: any) {
                // Try alternative endpoint formats
                try {
                  // Try without /restapi/ prefix
                  subtasksResponse = await client.get(
                    `/portal/${portal}/projects/${correctProjectId}/tasks/${taskId}/subtasks/`
                  );
                  
                  if (subtasksResponse.data.response?.result?.subtasks) {
                    subtasks = subtasksResponse.data.response.result.subtasks;
                  } else if (subtasksResponse.data.subtasks) {
                    subtasks = subtasksResponse.data.subtasks;
                  } else if (Array.isArray(subtasksResponse.data)) {
                    subtasks = subtasksResponse.data;
                  }
                } catch (altError: any) {
                  // If all fail, check if task has subtasks already embedded
                  if (task.subtasks && Array.isArray(task.subtasks) && task.subtasks.length > 0) {
                    subtasks = task.subtasks;
                    console.log(`✅ Using embedded subtasks for task ${taskId} (${subtasks.length} subtasks)`);
                  } else {
                    // Check for subtasks in different possible locations
                    if (task.sub_tasks && Array.isArray(task.sub_tasks) && task.sub_tasks.length > 0) {
                      subtasks = task.sub_tasks;
                      console.log(`✅ Using sub_tasks field for task ${taskId} (${subtasks.length} subtasks)`);
                    } else if (task.subtask_list && Array.isArray(task.subtask_list) && task.subtask_list.length > 0) {
                      subtasks = task.subtask_list;
                      console.log(`✅ Using subtask_list field for task ${taskId} (${subtasks.length} subtasks)`);
                    } else {
                      // Log task structure to help debug
                      console.log(`🔍 Task structure for ${taskId}:`, JSON.stringify(Object.keys(task), null, 2));
                      console.log(`   Has 'subtasks' field:`, !!task.subtasks);
                      console.log(`   Has 'sub_tasks' field:`, !!task.sub_tasks);
                      console.log(`   Has 'subtask_list' field:`, !!task.subtask_list);
                      // Don't throw, just return empty subtasks
                      subtasks = [];
                    }
                  }
                }
              }
            }
            
            return {
              ...task,
              subtasks: subtasks || []
            };
          } catch (subtaskError: any) {
            // If subtasks endpoint fails, check if task already has subtasks embedded
            if (task.subtasks && Array.isArray(task.subtasks) && task.subtasks.length > 0) {
              console.log(`✅ Using embedded subtasks for task ${task.id_string || task.id} (${task.subtasks.length} subtasks)`);
              return {
                ...task,
                subtasks: task.subtasks
              };
            }
            
            // If subtasks endpoint fails, just return task without subtasks
            console.warn(`Failed to fetch subtasks for task ${task.id_string || task.id}:`, subtaskError.response?.data?.error?.message || subtaskError.message);
            return {
              ...task,
              subtasks: []
            };
          }
        })
      );

      // Log summary of what was fetched
      const totalSubtasks = tasksWithSubtasks.reduce((sum, task) => sum + (task.subtasks?.length || 0), 0);
      console.log(`\n✅ Task Fetching Complete:`);
      console.log(`   - Total Tasks: ${tasksWithSubtasks.length}`);
      console.log(`   - Total Subtasks: ${totalSubtasks}`);
      tasksWithSubtasks.forEach((task, index) => {
        const subtaskCount = task.subtasks?.length || 0;
        if (subtaskCount > 0) {
          console.log(`   - Task ${index + 1}: "${task.name || task.task_name || 'Unnamed'}" has ${subtaskCount} subtask(s)`);
        }
      });
      console.log(`\n`);

      return tasksWithSubtasks;
    } catch (error: any) {
      console.error('Error fetching tasks:', error.response?.data || error.message);
      throw new Error(`Failed to fetch tasks: ${error.response?.data?.error?.message || error.message}`);
    }
  }

  /**
   * Save or update tokens for a user
   */
  async saveTokens(userId: number, tokenData: ZohoTokenResponse): Promise<void> {
    console.log(`[SAVE_TOKENS] Starting save for user ${userId}`);
    console.log(`[SAVE_TOKENS] Token data:`, {
      has_access_token: !!tokenData.access_token,
      access_token_length: tokenData.access_token?.length || 0,
      has_refresh_token: !!tokenData.refresh_token,
      refresh_token_length: tokenData.refresh_token?.length || 0,
      expires_in: tokenData.expires_in,
      token_type: tokenData.token_type
    });
    
    // Validate required fields
    if (!tokenData.access_token || tokenData.access_token.trim() === '') {
      console.error(`[SAVE_TOKENS] ERROR: access_token is missing for user ${userId}`);
      throw new Error('Cannot save tokens: access_token is missing, null, or empty');
    }

    if (!tokenData.refresh_token || tokenData.refresh_token.trim() === '') {
      console.error(`[SAVE_TOKENS] ERROR: refresh_token is missing for user ${userId}`);
      throw new Error('Cannot save tokens: refresh_token is missing, null, or empty');
    }

    // Validate expires_in and provide default (3600 seconds = 1 hour)
    const expiresIn = tokenData.expires_in && typeof tokenData.expires_in === 'number' && !isNaN(tokenData.expires_in) && tokenData.expires_in > 0
      ? tokenData.expires_in 
      : 3600;
    
    // Calculate expiration time more robustly
    const now = Date.now();
    const expiresAt = new Date(now + (expiresIn * 1000));
    
    // Validate the date is valid
    if (isNaN(expiresAt.getTime())) {
      throw new Error(`Invalid expiration date calculated. expires_in: ${tokenData.expires_in}, calculated: ${expiresAt}`);
    }
    
    console.log(`Saving tokens for user ${userId}, expires_in: ${expiresIn}, expires_at: ${expiresAt.toISOString()}`);

    const result = await pool.query(
      `INSERT INTO zoho_tokens 
       (user_id, access_token, refresh_token, token_type, expires_in, expires_at, scope)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       ON CONFLICT (user_id) 
       DO UPDATE SET 
         access_token = EXCLUDED.access_token,
         refresh_token = EXCLUDED.refresh_token,
         token_type = EXCLUDED.token_type,
         expires_in = EXCLUDED.expires_in,
         expires_at = EXCLUDED.expires_at,
         scope = EXCLUDED.scope,
         updated_at = CURRENT_TIMESTAMP
       RETURNING id, user_id, created_at, expires_at`,
      [
        userId,
        tokenData.access_token,
        tokenData.refresh_token,
        tokenData.token_type || 'Bearer',
        expiresIn,
        expiresAt,
        tokenData.scope || '',
      ]
    );
    
    if (result.rows.length === 0) {
      console.error(`[SAVE_TOKENS] ERROR: No rows returned after insert for user ${userId}`);
      throw new Error('Failed to save tokens: No rows returned from database');
    }
    
    console.log(`[SAVE_TOKENS] ✅ Successfully saved tokens for user ${userId}:`, {
      token_id: result.rows[0].id,
      user_id: result.rows[0].user_id,
      created_at: result.rows[0].created_at,
      expires_at: result.rows[0].expires_at
    });
    
    // Verify the token was actually saved
    const verifyResult = await pool.query(
      'SELECT id, user_id, expires_at FROM zoho_tokens WHERE user_id = $1',
      [userId]
    );
    
    if (verifyResult.rows.length === 0) {
      console.error(`[SAVE_TOKENS] ERROR: Verification failed - token not found after save for user ${userId}`);
      throw new Error('Failed to verify token save: Token not found after insert');
    }
    
    console.log(`[SAVE_TOKENS] ✅ Verified token saved for user ${userId}`);
  }

  /**
   * Check if user has valid Zoho token
   */
  async hasValidToken(userId: number): Promise<boolean> {
    try {
      const result = await pool.query(
        'SELECT expires_at FROM zoho_tokens WHERE user_id = $1',
        [userId]
      );

      if (result.rows.length === 0) {
        return false;
      }

      const expiresAt = new Date(result.rows[0].expires_at);
      return expiresAt > new Date();
    } catch (error) {
      return false;
    }
  }

  /**
   * Delete tokens for a user
   */
  async revokeTokens(userId: number): Promise<void> {
    await pool.query('DELETE FROM zoho_tokens WHERE user_id = $1', [userId]);
  }
}

export default new ZohoService();

