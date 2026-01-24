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

interface ZohoProjectMember {
  id: string;
  name: string;
  email: string;
  role: string; // Project role: "Admin", "Manager", "Employee", etc.
  status: string; // "active", "inactive", etc.
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
      'ZohoProjects.users.READ',  // Required for reading project users/members
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

      const data = response.data;

      // Check if Zoho returned an error in the response (even with 200 status)
      if (data.error) {
        console.error('Zoho token refresh error:', {
          error: data.error,
          error_description: data.error_description,
          full_response: data
        });
        throw new Error(`Zoho token refresh failed: ${data.error} - ${data.error_description || 'No description provided'}`);
      }

      // Validate that we have an access_token
      if (!data.access_token) {
        console.error('Zoho token refresh response missing access_token:', {
          response_keys: Object.keys(data),
          full_response: data
        });
        throw new Error('Zoho token refresh response missing access_token. The refresh token may be invalid or expired. Please re-authorize.');
      }

      return data;
    } catch (error: any) {
      // If it's already our custom error, re-throw it
      if (error.message && error.message.includes('Zoho token refresh')) {
        throw error;
      }
      
      console.error('Error refreshing token:', {
        error: error.response?.data || error.message,
        status: error.response?.status,
        statusText: error.response?.statusText,
        full_error: error.response?.data
      });
      throw new Error(`Failed to refresh token: ${error.response?.data?.error || error.message}`);
    }
  }

  /**
   * Get or refresh access token for a user
   */
  async getValidAccessToken(userId: number): Promise<string> {
    const result = await pool.query(
      'SELECT access_token, refresh_token, expires_at FROM public.zoho_tokens WHERE user_id = $1',
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
        `UPDATE public.zoho_tokens 
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
        // Try to find the portal that contains this project
        // First, try to get the project to see which portal it's in
        for (const p of portals) {
          try {
            const testResponse = await client.get(`/restapi/portal/${p.id}/projects/${projectId}/`);
            if (testResponse.status === 200) {
              portal = p.id;
              console.log(`[ZohoService] Found project in portal: ${p.id} (${p.name || p.portal_name || p.id_string})`);
              break;
            }
          } catch (e) {
            // Try next portal
            continue;
          }
        }
        
        // If still no portal found, use first portal
        if (!portal) {
          portal = portals[0].id;
          console.log(`[ZohoService] Using first available portal: ${portal}`);
        }
      }

      console.log(`[ZohoService] Fetching project members for projectId: ${projectId}, portalId: ${portal}`);

      let response: any = null;
      let lastError: any = null;
      
      // Find the project in portals
      const portals = await this.getPortals(userId);
      let foundPortal = portal;
      let projectFromList: any = null;
      
      // Search all portals to find which one contains this project
      for (const p of portals) {
        try {
          const projectsList = await client.get(`/restapi/portal/${p.id}/projects/`);
          const projects = projectsList.data?.response?.result?.projects || 
                          projectsList.data?.projects || 
                          (Array.isArray(projectsList.data) ? projectsList.data : []);
          
          // Try multiple ways to match the project ID
          const foundProject = Array.isArray(projects) 
            ? projects.find((proj: any) => {
                const projId = proj.id || proj.id_string;
                const projIdStr = String(projId || '');
                const searchIdStr = String(projectId || '');
                return proj.id === projectId || proj.id_string === projectId || 
                       projIdStr === searchIdStr ||
                       (!isNaN(Number(projId)) && !isNaN(Number(projectId)) && Number(projId) === Number(projectId));
              })
            : null;
          
          if (foundProject) {
            foundPortal = p.id;
            projectFromList = foundProject;
            console.log(`[ZohoService] ✅ Found project "${foundProject.name}" in portal ${p.id}`);
            
            // Log all keys in project object for debugging
            console.log(`[ZohoService] Project object keys: ${Object.keys(foundProject).join(', ')}`);
            
            // Check if project data already contains users/members
            if (foundProject.users && Array.isArray(foundProject.users)) {
              console.log(`[ZohoService] ✅ Found ${foundProject.users.length} users in project list response`);
              return foundProject.users;
            }
            if (foundProject.project_users && Array.isArray(foundProject.project_users)) {
              console.log(`[ZohoService] ✅ Found ${foundProject.project_users.length} project_users in project list response`);
              return foundProject.project_users;
            }
            if (foundProject.members && Array.isArray(foundProject.members)) {
              console.log(`[ZohoService] ✅ Found ${foundProject.members.length} members in project list response`);
              return foundProject.members;
            }
            // Log if users field exists but is not an array
            if (foundProject.users && !Array.isArray(foundProject.users)) {
              console.log(`[ZohoService] ⚠️  Project has 'users' field but it's not an array: ${typeof foundProject.users}`);
            }
            break;
          }
        } catch (e: any) {
          continue;
        }
      }
      
      if (!projectFromList) {
        throw new Error(`Project ${projectId} not found in any portal. Please verify the project ID.`);
      }
      
      portal = foundPortal;
      const projectIdString = projectFromList?.id_string || projectId;
      
      // Try fetching project details with V3 API first to check for users
      const projectDetailEndpoints = [
        `/api/v3/portal/${portal}/projects/${projectIdString}`,
        `/api/v3/portal/${portal}/projects/${projectId}`,
      ];
      
      let fullProject: any = null;
      for (const endpoint of projectDetailEndpoints) {
        try {
          const fullProjectResponse = await client.get(endpoint);
          fullProject = fullProjectResponse.data?.response?.result || fullProjectResponse.data;
          
          // Check for users in various possible locations
          // Log project structure for debugging
          if (fullProject) {
            console.log(`[ZohoService] Project details keys: ${Object.keys(fullProject).join(', ')}`);
            if (fullProject.users) {
              console.log(`[ZohoService] Project has 'users': ${Array.isArray(fullProject.users) ? `array with ${fullProject.users.length} items` : typeof fullProject.users}`);
            }
            if (fullProject.project_users) {
              console.log(`[ZohoService] Project has 'project_users': ${Array.isArray(fullProject.project_users) ? `array with ${fullProject.project_users.length} items` : typeof fullProject.project_users}`);
            }
            // Check for user-related fields
            if (fullProject.owner) {
              console.log(`[ZohoService] Project has 'owner': ${typeof fullProject.owner}`);
            }
            if (fullProject.project_manager) {
              console.log(`[ZohoService] Project has 'project_manager': ${typeof fullProject.project_manager}`);
            }
            if (fullProject.stakeholders) {
              console.log(`[ZohoService] Project has 'stakeholders': ${Array.isArray(fullProject.stakeholders) ? `array with ${fullProject.stakeholders.length} items` : typeof fullProject.stakeholders}`);
            }
          }
          
          if (fullProject?.users && Array.isArray(fullProject.users)) {
            console.log(`[ZohoService] ✅ Found ${fullProject.users.length} users in project details`);
            return fullProject.users;
          }
          if (fullProject?.project_users && Array.isArray(fullProject.project_users)) {
            console.log(`[ZohoService] ✅ Found ${fullProject.project_users.length} project_users in project details`);
            return fullProject.project_users;
          }
          if (fullProject?.members && Array.isArray(fullProject.members)) {
            console.log(`[ZohoService] ✅ Found ${fullProject.members.length} members in project details`);
            return fullProject.members;
          }
          
          // Extract users from project fields like owner, project_manager, stakeholders
          const extractedUsers: any[] = [];
          if (fullProject) {
            // Extract owner
            if (fullProject.owner && typeof fullProject.owner === 'object') {
              const owner = fullProject.owner;
              if (owner.email || owner.zpuid || owner.zuid || owner.id) {
                extractedUsers.push({
                  id: owner.zpuid || owner.zuid || owner.id,
                  zuid: owner.zuid,
                  zpuid: owner.zpuid,
                  name: owner.name || owner.display_name || `${owner.first_name || ''} ${owner.last_name || ''}`.trim(),
                  email: owner.email,
                  first_name: owner.first_name,
                  last_name: owner.last_name,
                  role: 'admin' // Project owner typically has admin role
                });
                console.log(`[ZohoService] Extracted owner: ${owner.email || owner.name || owner.id}`);
              }
            }
            
            // Extract project manager
            if (fullProject.project_manager && typeof fullProject.project_manager === 'object') {
              const pm = fullProject.project_manager;
              if (pm.email || pm.zpuid || pm.zuid || pm.id) {
                extractedUsers.push({
                  id: pm.zpuid || pm.zuid || pm.id,
                  zuid: pm.zuid,
                  zpuid: pm.zpuid,
                  name: pm.name || pm.display_name || `${pm.first_name || ''} ${pm.last_name || ''}`.trim(),
                  email: pm.email,
                  first_name: pm.first_name,
                  last_name: pm.last_name,
                  role: 'project_manager'
                });
                console.log(`[ZohoService] Extracted project manager: ${pm.email || pm.name || pm.id}`);
              }
            }
            
            // Extract stakeholders
            if (fullProject.stakeholders && Array.isArray(fullProject.stakeholders)) {
              fullProject.stakeholders.forEach((stakeholder: any) => {
                if (stakeholder && typeof stakeholder === 'object' && (stakeholder.email || stakeholder.zpuid || stakeholder.zuid || stakeholder.id)) {
                  extractedUsers.push({
                    id: stakeholder.zpuid || stakeholder.zuid || stakeholder.id,
                    zuid: stakeholder.zuid,
                    zpuid: stakeholder.zpuid,
                    name: stakeholder.name || stakeholder.display_name || `${stakeholder.first_name || ''} ${stakeholder.last_name || ''}`.trim(),
                    email: stakeholder.email,
                    first_name: stakeholder.first_name,
                    last_name: stakeholder.last_name,
                    role: stakeholder.role || 'engineer'
                  });
                  console.log(`[ZohoService] Extracted stakeholder: ${stakeholder.email || stakeholder.name || stakeholder.id}`);
                }
              });
            }
            
            // Extract created_by and updated_by
            if (fullProject.created_by && typeof fullProject.created_by === 'object') {
              const creator = fullProject.created_by;
              if (creator.email || creator.zpuid || creator.zuid || creator.id) {
                extractedUsers.push({
                  id: creator.zpuid || creator.zuid || creator.id,
                  zuid: creator.zuid,
                  zpuid: creator.zpuid,
                  name: creator.name || creator.display_name || `${creator.first_name || ''} ${creator.last_name || ''}`.trim(),
                  email: creator.email,
                  first_name: creator.first_name,
                  last_name: creator.last_name,
                  role: 'admin'
                });
                console.log(`[ZohoService] Extracted creator: ${creator.email || creator.name || creator.id}`);
              }
            }
            
            if (fullProject.updated_by && typeof fullProject.updated_by === 'object') {
              const updater = fullProject.updated_by;
              if (updater.email || updater.zpuid || updater.zuid || updater.id) {
                extractedUsers.push({
                  id: updater.zpuid || updater.zuid || updater.id,
                  zuid: updater.zuid,
                  zpuid: updater.zpuid,
                  name: updater.name || updater.display_name || `${updater.first_name || ''} ${updater.last_name || ''}`.trim(),
                  email: updater.email,
                  first_name: updater.first_name,
                  last_name: updater.last_name,
                  role: 'engineer'
                });
                console.log(`[ZohoService] Extracted updater: ${updater.email || updater.name || updater.id}`);
              }
            }
            
            // Remove duplicates
            const uniqueExtracted = extractedUsers.filter((user, index, self) => 
              index === self.findIndex((u) => 
                (u.email && u.email === user.email) ||
                (u.zpuid && u.zpuid === user.zpuid) ||
                (u.zuid && u.zuid === user.zuid) ||
                (u.id && u.id === user.id)
              )
            );
            
            if (uniqueExtracted.length > 0) {
              console.log(`[ZohoService] ✅ Extracted ${uniqueExtracted.length} users from project fields (owner, PM, stakeholders, etc.)`);
              // Don't return here - continue to try tasks extraction for more users
            }
          }
          
          // Don't break - continue to try other endpoints and task extraction
        } catch (projectDetailsError: any) {
          continue;
        }
      }
      
      // Try multiple endpoint variations for getting project members
      // Use id_string for V3 API as it's more reliable
      const endpointVariations = [
        `/api/v3/portal/${portal}/projects/${projectIdString}/users`,
        `/api/v3/portal/${portal}/projects/${projectIdString}/users/`,
        `/api/v3/portal/${portal}/projects/${projectId}/users`,
        `/api/v3/portal/${portal}/projects/${projectId}/users/`,
        `/restapi/portal/${portal}/projects/${projectIdString}/users/`,
        `/restapi/portal/${portal}/projects/${projectId}/users/`,
        `/restapi/portal/${portal}/projects/${projectIdString}/people/`,
        `/restapi/portal/${portal}/projects/${projectId}/people/`,
        // Try with additional query parameters
        `/api/v3/portal/${portal}/projects/${projectIdString}/users?type=all`,
        `/restapi/portal/${portal}/projects/${projectIdString}/users/?type=all`,
        // Try project details with users included
        `/api/v3/portal/${portal}/projects/${projectIdString}?include=users`,
        `/api/v3/portal/${portal}/projects/${projectIdString}?include=project_users`,
      ];
      
      for (const endpoint of endpointVariations) {
        try {
          console.log(`[ZohoService] Trying endpoint: ${endpoint}`);
          response = await client.get(endpoint);
          console.log(`[ZohoService] ✅ Success with endpoint: ${endpoint} (status: ${response.status})`);
          
          // Extract users from response immediately
          const responseData = response.data?.response?.result || response.data;
          let members: ZohoProjectMember[] = [];
          
          // Log response structure for debugging
          if (responseData) {
            console.log(`[ZohoService] Response keys: ${Object.keys(responseData).join(', ')}`);
            if (responseData.users) {
              console.log(`[ZohoService] Found 'users' field: ${Array.isArray(responseData.users) ? `array with ${responseData.users.length} items` : typeof responseData.users}`);
            }
            if (responseData.project_users) {
              console.log(`[ZohoService] Found 'project_users' field: ${Array.isArray(responseData.project_users) ? `array with ${responseData.project_users.length} items` : typeof responseData.project_users}`);
            }
          }
          
          if (responseData?.users && Array.isArray(responseData.users)) {
            members = responseData.users;
          } else if (responseData?.project_users && Array.isArray(responseData.project_users)) {
            members = responseData.project_users;
          } else if (responseData?.members && Array.isArray(responseData.members)) {
            members = responseData.members;
          } else if (responseData?.people && Array.isArray(responseData.people)) {
            members = responseData.people;
          } else if (Array.isArray(responseData)) {
            members = responseData;
          } else if (responseData?.response?.result?.users && Array.isArray(responseData.response.result.users)) {
            members = responseData.response.result.users;
          } else if (responseData?.response?.result?.project_users && Array.isArray(responseData.response.result.project_users)) {
            members = responseData.response.result.project_users;
          }
          
          if (members.length > 0) {
            console.log(`[ZohoService] ✅ Found ${members.length} project members from API endpoint: ${endpoint}`);
            return members;
          } else {
            console.log(`[ZohoService] ⚠️  Endpoint ${endpoint} returned success but no members found`);
          }
          
          // If we got a response but no members, continue to next endpoint
          // Don't break here - try all endpoints
        } catch (error: any) {
          const status = error.response?.status;
          const errorMsg = error.response?.data?.error?.message || error.message;
          console.log(`[ZohoService] ❌ Endpoint ${endpoint} failed: ${status || 'N/A'} - ${errorMsg}`);
          if (error.response?.status === 404) {
            lastError = error;
            continue;
          } else {
            lastError = error;
            continue;
          }
        }
      }
      
      // If all direct endpoints failed or returned no members, try alternative approaches
      // Always try task extraction as fallback, even if we got a response
      if (!response && lastError) {
        // Approach 1: Try getting project teams/usergroups
        try {
          const usergroupsEndpoints = [
            `/api/v3/portal/${portal}/projects/${projectId}/usergroups`,
            `/api/v3/portal/${portal}/projects/${projectId}/teams`,
            `/restapi/portal/${portal}/projects/${projectId}/usergroups/`,
          ];
          
          let usergroupsResponse: any = null;
          for (const endpoint of usergroupsEndpoints) {
            try {
              usergroupsResponse = await client.get(endpoint);
              break;
            } catch (error: any) {
              continue;
            }
          }
          
          if (usergroupsResponse) {
            const usergroups = usergroupsResponse.data?.response?.result?.usergroups || 
                              usergroupsResponse.data?.response?.result?.teams ||
                              usergroupsResponse.data?.usergroups || 
                              usergroupsResponse.data?.teams || 
                              usergroupsResponse.data || [];
            
            if (Array.isArray(usergroups) && usergroups.length > 0) {
              const allMembers: any[] = [];
              usergroups.forEach((group: any) => {
                if (group.users && Array.isArray(group.users)) {
                  allMembers.push(...group.users);
                }
                if (group.members && Array.isArray(group.members)) {
                  allMembers.push(...group.members);
                }
              });
              
              const uniqueMembers = allMembers.filter((member, index, self) => 
                index === self.findIndex((m) => 
                  (m.id && m.id === member.id) || 
                  (m.email && m.email === member.email) ||
                  (m.Email && m.Email === member.Email) || 
                  (m.user_id && m.user_id === member.user_id)
                )
              );
              
              if (uniqueMembers.length > 0) {
                console.log(`[ZohoService] ✅ Found ${uniqueMembers.length} unique members from usergroups/teams`);
                return uniqueMembers;
              }
            }
          }
        } catch (usergroupsError: any) {
          // Continue to next approach
        }
        
        // Approach 2: Try getting tasks and extract assignees
        // Also combine with users extracted from project fields
        let allExtractedUsers: any[] = [];
        
        // Add users extracted from project details if we have them (from earlier in the function)
        if (fullProject) {
          const extractedFromProject: any[] = [];
          
          // Extract owner
          if (fullProject.owner && typeof fullProject.owner === 'object') {
            const owner = fullProject.owner;
            if (owner.email || owner.zpuid || owner.zuid || owner.id) {
              extractedFromProject.push({
                id: owner.zpuid || owner.zuid || owner.id,
                zuid: owner.zuid,
                zpuid: owner.zpuid,
                name: owner.name || owner.display_name || `${owner.first_name || ''} ${owner.last_name || ''}`.trim(),
                email: owner.email,
                first_name: owner.first_name,
                last_name: owner.last_name,
                role: 'admin'
              });
            }
          }
          
          // Extract project manager
          if (fullProject.project_manager && typeof fullProject.project_manager === 'object') {
            const pm = fullProject.project_manager;
            if (pm.email || pm.zpuid || pm.zuid || pm.id) {
              extractedFromProject.push({
                id: pm.zpuid || pm.zuid || pm.id,
                zuid: pm.zuid,
                zpuid: pm.zpuid,
                name: pm.name || pm.display_name || `${pm.first_name || ''} ${pm.last_name || ''}`.trim(),
                email: pm.email,
                first_name: pm.first_name,
                last_name: pm.last_name,
                role: 'project_manager'
              });
            }
          }
          
          // Extract stakeholders
          if (fullProject.stakeholders && Array.isArray(fullProject.stakeholders)) {
            fullProject.stakeholders.forEach((stakeholder: any) => {
              if (stakeholder && typeof stakeholder === 'object' && (stakeholder.email || stakeholder.zpuid || stakeholder.zuid || stakeholder.id)) {
                extractedFromProject.push({
                  id: stakeholder.zpuid || stakeholder.zuid || stakeholder.id,
                  zuid: stakeholder.zuid,
                  zpuid: stakeholder.zpuid,
                  name: stakeholder.name || stakeholder.display_name || `${stakeholder.first_name || ''} ${stakeholder.last_name || ''}`.trim(),
                  email: stakeholder.email,
                  first_name: stakeholder.first_name,
                  last_name: stakeholder.last_name,
                  role: stakeholder.role || 'engineer'
                });
              }
            });
          }
          
          // Extract created_by and updated_by
          if (fullProject.created_by && typeof fullProject.created_by === 'object') {
            const creator = fullProject.created_by;
            if (creator.email || creator.zpuid || creator.zuid || creator.id) {
              extractedFromProject.push({
                id: creator.zpuid || creator.zuid || creator.id,
                zuid: creator.zuid,
                zpuid: creator.zpuid,
                name: creator.name || creator.display_name || `${creator.first_name || ''} ${creator.last_name || ''}`.trim(),
                email: creator.email,
                first_name: creator.first_name,
                last_name: creator.last_name,
                role: 'admin'
              });
            }
          }
          
          if (fullProject.updated_by && typeof fullProject.updated_by === 'object') {
            const updater = fullProject.updated_by;
            if (updater.email || updater.zpuid || updater.zuid || updater.id) {
              extractedFromProject.push({
                id: updater.zpuid || updater.zuid || updater.id,
                zuid: updater.zuid,
                zpuid: updater.zpuid,
                name: updater.name || updater.display_name || `${updater.first_name || ''} ${updater.last_name || ''}`.trim(),
                email: updater.email,
                first_name: updater.first_name,
                last_name: updater.last_name,
                role: 'engineer'
              });
            }
          }
          
          allExtractedUsers.push(...extractedFromProject);
          if (extractedFromProject.length > 0) {
            console.log(`[ZohoService] ✅ Extracted ${extractedFromProject.length} users from project fields (owner, PM, stakeholders, etc.)`);
          }
        }
        
        try {
          const tasksEndpoints = [
            `/api/v3/portal/${portal}/projects/${projectIdString}/tasks`,
            `/api/v3/portal/${portal}/projects/${projectId}/tasks`,
            `/restapi/portal/${portal}/projects/${projectIdString}/tasks/`,
          ];
          
          let tasksResponse: any = null;
          for (const endpoint of tasksEndpoints) {
            try {
              console.log(`[ZohoService] Trying tasks endpoint: ${endpoint}`);
              tasksResponse = await client.get(endpoint);
              console.log(`[ZohoService] ✅ Success with tasks endpoint: ${endpoint}`);
              break;
            } catch (error: any) {
              console.log(`[ZohoService] ❌ Tasks endpoint ${endpoint} failed: ${error.response?.status || 'N/A'} - ${error.message}`);
              continue;
            }
          }
          
          if (tasksResponse) {
            const tasksData = tasksResponse.data?.response?.result || tasksResponse.data;
            const tasks = tasksData?.tasks || (Array.isArray(tasksData) ? tasksData : []);
            
            if (Array.isArray(tasks) && tasks.length > 0) {
              console.log(`[ZohoService] Found ${tasks.length} tasks, extracting users...`);
              
              // Extract unique users from task assignees
              const allAssignees: any[] = [];
              tasks.forEach((task: any) => {
                // Extract from created_by object (V3 API format)
                if (task.created_by && typeof task.created_by === 'object') {
                  const createdBy = task.created_by;
                  if (createdBy.email || createdBy.zpuid || createdBy.zuid) {
                    allAssignees.push({
                      id: createdBy.zpuid || createdBy.zuid || createdBy.id,
                      zuid: createdBy.zuid,
                      zpuid: createdBy.zpuid,
                      name: createdBy.name || `${createdBy.first_name || ''} ${createdBy.last_name || ''}`.trim(),
                      email: createdBy.email,
                      first_name: createdBy.first_name,
                      last_name: createdBy.last_name,
                      role: 'engineer' // Default role, will be updated from project profile if available
                    });
                  }
                }
                
                // Extract from owners_and_work field (V3 API format)
                if (task.owners_and_work) {
                  if (Array.isArray(task.owners_and_work)) {
                    task.owners_and_work.forEach((ownerWork: any) => {
                      const owner = ownerWork?.owner || ownerWork;
                      if (owner && typeof owner === 'object' && (owner.email || owner.zpuid || owner.zuid)) {
                        allAssignees.push({
                          id: owner.zpuid || owner.zuid || owner.id,
                          zuid: owner.zuid,
                          zpuid: owner.zpuid,
                          name: owner.name || `${owner.first_name || ''} ${owner.last_name || ''}`.trim(),
                          email: owner.email,
                          first_name: owner.first_name,
                          last_name: owner.last_name,
                          role: owner.role || ownerWork?.role || 'engineer'
                        });
                      }
                    });
                  } else if (typeof task.owners_and_work === 'object') {
                    // Single owner object or object with owner property
                    const owner = task.owners_and_work.owner || task.owners_and_work;
                    if (owner && typeof owner === 'object' && (owner.email || owner.zpuid || owner.zuid)) {
                      allAssignees.push({
                        id: owner.zpuid || owner.zuid || owner.id,
                        zuid: owner.zuid,
                        zpuid: owner.zpuid,
                        name: owner.name || `${owner.first_name || ''} ${owner.last_name || ''}`.trim(),
                        email: owner.email,
                        first_name: owner.first_name,
                        last_name: owner.last_name,
                        role: owner.role || 'engineer'
                      });
                    }
                  }
                }
                
                // Check other possible user fields (fallback)
                if (task.owner && typeof task.owner === 'object' && (task.owner.id || task.owner.email)) {
                  allAssignees.push(task.owner);
                }
                if (task.owner_id && task.owner_name) {
                  allAssignees.push({
                    id: task.owner_id,
                    name: task.owner_name,
                    email: task.owner_email || task.owner_email_id,
                    role: task.owner_role || 'engineer'
                  });
                }
                if (task.assignee && typeof task.assignee === 'object' && (task.assignee.id || task.assignee.email)) {
                  allAssignees.push(task.assignee);
                }
                if (task.assignees && Array.isArray(task.assignees)) {
                  allAssignees.push(...task.assignees);
                }
              });
              
              // Also extract from project owner and other project-level users
              if (projectFromList) {
                // Add project owner
                if (projectFromList.owner_email && projectFromList.owner_name) {
                  allAssignees.push({
                    id: projectFromList.owner_zpuid || projectFromList.owner_id,
                    zuid: projectFromList.owner_id,
                    zpuid: projectFromList.owner_zpuid,
                    name: projectFromList.owner_name,
                    email: projectFromList.owner_email,
                    role: projectFromList.role || 'admin' // Project owner typically has admin role
                  });
                }
                
                // Add project creator
                if (projectFromList.created_by_id && projectFromList.created_by) {
                  allAssignees.push({
                    id: projectFromList.created_by_zpuid || projectFromList.created_by_id,
                    zuid: projectFromList.created_by_id,
                    zpuid: projectFromList.created_by_zpuid,
                    name: projectFromList.created_by,
                    email: projectFromList.owner_email, // May not have separate email
                    role: 'admin'
                  });
                }
              }
              
              // Combine with users extracted from project fields
              allExtractedUsers.push(...allAssignees);
              
              // Remove duplicates by email, zpuid, or zuid
              const uniqueAssignees = allExtractedUsers.filter((user, index, self) => 
                index === self.findIndex((u) => 
                  (u.email && u.email === user.email) ||
                  (u.zpuid && u.zpuid === user.zpuid) ||
                  (u.zuid && u.zuid === user.zuid) ||
                  (u.id && u.id === user.id) ||
                  (u.Email && u.Email === user.Email)
                )
              );
              
              if (uniqueAssignees.length > 0) {
                console.log(`[ZohoService] ✅ Found ${uniqueAssignees.length} unique users from tasks and project data (${allExtractedUsers.length - allAssignees.length} from project fields, ${allAssignees.length} from tasks)`);
                return uniqueAssignees;
              }
            } else {
              console.log(`[ZohoService] ⚠️  Tasks response received but no tasks found or tasks is not an array`);
            }
          } else {
            console.log(`[ZohoService] ⚠️  No tasks response received from any endpoint`);
          }
          
          // If we have users from project fields but no tasks, return those
          if (allExtractedUsers.length > 0) {
            const uniqueUsers = allExtractedUsers.filter((user, index, self) => 
              index === self.findIndex((u) => 
                (u.email && u.email === user.email) ||
                (u.zpuid && u.zpuid === user.zpuid) ||
                (u.zuid && u.zuid === user.zuid) ||
                (u.id && u.id === user.id)
              )
            );
            if (uniqueUsers.length > 0) {
              console.log(`[ZohoService] ✅ Returning ${uniqueUsers.length} users extracted from project fields (no tasks found)`);
              return uniqueUsers;
            }
          }
        } catch (tasksError: any) {
          console.log(`[ZohoService] ⚠️  Error extracting from tasks: ${tasksError.message}`);
          // If we have users from project fields, return those even if tasks extraction failed
          if (allExtractedUsers.length > 0) {
            const uniqueUsers = allExtractedUsers.filter((user, index, self) => 
              index === self.findIndex((u) => 
                (u.email && u.email === user.email) ||
                (u.zpuid && u.zpuid === user.zpuid) ||
                (u.zuid && u.zuid === user.zuid) ||
                (u.id && u.id === user.id)
              )
            );
            if (uniqueUsers.length > 0) {
              console.log(`[ZohoService] ✅ Returning ${uniqueUsers.length} users extracted from project fields (tasks extraction failed)`);
              return uniqueUsers;
            }
          }
        }
        
        // If all approaches failed, throw error
        console.error(`[ZohoService] All endpoint variations failed. Last error:`, lastError.response?.data?.error?.message || lastError.message);
        throw new Error(
          `Failed to fetch project members: ${lastError.response?.data?.error?.message || lastError.message}`
        );
      }
      
      // If we got a response but no members, try task extraction as fallback
      // This handles the case where endpoints return 200 but no members
      if (response) {
        // Handle different response structures
        let members: ZohoProjectMember[] = [];
        
        if (response.data?.response?.result?.users) {
          members = response.data.response.result.users;
        } else if (response.data?.response?.result?.project_users) {
          members = response.data.response.result.project_users;
        } else if (response.data?.users) {
          members = response.data.users;
        } else if (response.data?.project_users) {
          members = response.data.project_users;
        } else if (Array.isArray(response.data)) {
          members = response.data;
        }

        if (members.length > 0) {
          console.log(`[ZohoService] ✅ Found ${members.length} project members from API`);
          return members;
        }
        // If response exists but no members, continue to task extraction below
        console.log(`[ZohoService] ⚠️  Response received but no members found, trying task extraction as fallback...`);
      }
      
      // Try task extraction as fallback (even if we got a response with no members)
      // Extract users from project fields and tasks
      let allExtractedUsers: any[] = [];
      
      // Add users extracted from project details if we have them
      if (fullProject) {
        const extractedFromProject: any[] = [];
        
        // Extract owner
        if (fullProject.owner && typeof fullProject.owner === 'object') {
          const owner = fullProject.owner;
          if (owner.email || owner.zpuid || owner.zuid || owner.id) {
            extractedFromProject.push({
              id: owner.zpuid || owner.zuid || owner.id,
              zuid: owner.zuid,
              zpuid: owner.zpuid,
              name: owner.name || owner.display_name || `${owner.first_name || ''} ${owner.last_name || ''}`.trim(),
              email: owner.email,
              first_name: owner.first_name,
              last_name: owner.last_name,
              role: 'admin'
            });
          }
        }
        
        // Extract project manager
        if (fullProject.project_manager && typeof fullProject.project_manager === 'object') {
          const pm = fullProject.project_manager;
          if (pm.email || pm.zpuid || pm.zuid || pm.id) {
            extractedFromProject.push({
              id: pm.zpuid || pm.zuid || pm.id,
              zuid: pm.zuid,
              zpuid: pm.zpuid,
              name: pm.name || pm.display_name || `${pm.first_name || ''} ${pm.last_name || ''}`.trim(),
              email: pm.email,
              first_name: pm.first_name,
              last_name: pm.last_name,
              role: 'project_manager'
            });
          }
        }
        
        // Extract stakeholders
        if (fullProject.stakeholders && Array.isArray(fullProject.stakeholders)) {
          fullProject.stakeholders.forEach((stakeholder: any) => {
            if (stakeholder && typeof stakeholder === 'object' && (stakeholder.email || stakeholder.zpuid || stakeholder.zuid || stakeholder.id)) {
              extractedFromProject.push({
                id: stakeholder.zpuid || stakeholder.zuid || stakeholder.id,
                zuid: stakeholder.zuid,
                zpuid: stakeholder.zpuid,
                name: stakeholder.name || stakeholder.display_name || `${stakeholder.first_name || ''} ${stakeholder.last_name || ''}`.trim(),
                email: stakeholder.email,
                first_name: stakeholder.first_name,
                last_name: stakeholder.last_name,
                role: stakeholder.role || 'engineer'
              });
            }
          });
        }
        
        // Extract created_by and updated_by
        if (fullProject.created_by && typeof fullProject.created_by === 'object') {
          const creator = fullProject.created_by;
          if (creator.email || creator.zpuid || creator.zuid || creator.id) {
            extractedFromProject.push({
              id: creator.zpuid || creator.zuid || creator.id,
              zuid: creator.zuid,
              zpuid: creator.zpuid,
              name: creator.name || creator.display_name || `${creator.first_name || ''} ${creator.last_name || ''}`.trim(),
              email: creator.email,
              first_name: creator.first_name,
              last_name: creator.last_name,
              role: 'admin'
            });
          }
        }
        
        if (fullProject.updated_by && typeof fullProject.updated_by === 'object') {
          const updater = fullProject.updated_by;
          if (updater.email || updater.zpuid || updater.zuid || updater.id) {
            extractedFromProject.push({
              id: updater.zpuid || updater.zuid || updater.id,
              zuid: updater.zuid,
              zpuid: updater.zpuid,
              name: updater.name || updater.display_name || `${updater.first_name || ''} ${updater.last_name || ''}`.trim(),
              email: updater.email,
              first_name: updater.first_name,
              last_name: updater.last_name,
              role: 'engineer'
            });
          }
        }
        
        allExtractedUsers.push(...extractedFromProject);
        if (extractedFromProject.length > 0) {
          console.log(`[ZohoService] ✅ Extracted ${extractedFromProject.length} users from project fields (owner, PM, stakeholders, etc.)`);
        }
      }
      
      // Try getting tasks and extract assignees
      try {
        const tasksEndpoints = [
          `/api/v3/portal/${portal}/projects/${projectIdString}/tasks`,
          `/api/v3/portal/${portal}/projects/${projectId}/tasks`,
          `/restapi/portal/${portal}/projects/${projectIdString}/tasks/`,
        ];
        
        let tasksResponse: any = null;
        for (const endpoint of tasksEndpoints) {
          try {
            console.log(`[ZohoService] Trying tasks endpoint: ${endpoint}`);
            tasksResponse = await client.get(endpoint);
            console.log(`[ZohoService] ✅ Success with tasks endpoint: ${endpoint}`);
            break;
          } catch (error: any) {
            console.log(`[ZohoService] ❌ Tasks endpoint ${endpoint} failed: ${error.response?.status || 'N/A'} - ${error.message}`);
            continue;
          }
        }
        
        if (tasksResponse) {
          const tasksData = tasksResponse.data?.response?.result || tasksResponse.data;
          const tasks = tasksData?.tasks || (Array.isArray(tasksData) ? tasksData : []);
          
          if (Array.isArray(tasks) && tasks.length > 0) {
            console.log(`[ZohoService] Found ${tasks.length} tasks, extracting users...`);
            
            // Extract unique users from task assignees
            const allAssignees: any[] = [];
            tasks.forEach((task: any) => {
              // Extract from created_by object (V3 API format)
              if (task.created_by && typeof task.created_by === 'object') {
                const createdBy = task.created_by;
                if (createdBy.email || createdBy.zpuid || createdBy.zuid) {
                  allAssignees.push({
                    id: createdBy.zpuid || createdBy.zuid || createdBy.id,
                    zuid: createdBy.zuid,
                    zpuid: createdBy.zpuid,
                    name: createdBy.name || `${createdBy.first_name || ''} ${createdBy.last_name || ''}`.trim(),
                    email: createdBy.email,
                    first_name: createdBy.first_name,
                    last_name: createdBy.last_name,
                    role: 'engineer'
                  });
                }
              }
              
              // Extract from owners_and_work field (V3 API format)
              if (task.owners_and_work) {
                if (Array.isArray(task.owners_and_work)) {
                  task.owners_and_work.forEach((ownerWork: any) => {
                    const owner = ownerWork?.owner || ownerWork;
                    if (owner && typeof owner === 'object' && (owner.email || owner.zpuid || owner.zuid)) {
                      allAssignees.push({
                        id: owner.zpuid || owner.zuid || owner.id,
                        zuid: owner.zuid,
                        zpuid: owner.zpuid,
                        name: owner.name || `${owner.first_name || ''} ${owner.last_name || ''}`.trim(),
                        email: owner.email,
                        first_name: owner.first_name,
                        last_name: owner.last_name,
                        role: owner.role || ownerWork?.role || 'engineer'
                      });
                    }
                  });
                } else if (typeof task.owners_and_work === 'object') {
                  const owner = task.owners_and_work.owner || task.owners_and_work;
                  if (owner && typeof owner === 'object' && (owner.email || owner.zpuid || owner.zuid)) {
                    allAssignees.push({
                      id: owner.zpuid || owner.zuid || owner.id,
                      zuid: owner.zuid,
                      zpuid: owner.zpuid,
                      name: owner.name || `${owner.first_name || ''} ${owner.last_name || ''}`.trim(),
                      email: owner.email,
                      first_name: owner.first_name,
                      last_name: owner.last_name,
                      role: owner.role || 'engineer'
                    });
                  }
                }
              }
              
              // Check other possible user fields
              if (task.owner && typeof task.owner === 'object' && (task.owner.id || task.owner.email)) {
                allAssignees.push(task.owner);
              }
              if (task.assignee && typeof task.assignee === 'object' && (task.assignee.id || task.assignee.email)) {
                allAssignees.push(task.assignee);
              }
              if (task.assignees && Array.isArray(task.assignees)) {
                allAssignees.push(...task.assignees);
              }
            });
            
            // Also extract from project owner
            if (projectFromList) {
              if (projectFromList.owner_email && projectFromList.owner_name) {
                allAssignees.push({
                  id: projectFromList.owner_zpuid || projectFromList.owner_id,
                  zuid: projectFromList.owner_id,
                  zpuid: projectFromList.owner_zpuid,
                  name: projectFromList.owner_name,
                  email: projectFromList.owner_email,
                  role: projectFromList.role || 'admin'
                });
              }
            }
            
            // Combine with users extracted from project fields
            allExtractedUsers.push(...allAssignees);
            
            // Remove duplicates
            const uniqueUsers = allExtractedUsers.filter((user, index, self) => 
              index === self.findIndex((u) => 
                (u.email && u.email === user.email) ||
                (u.zpuid && u.zpuid === user.zpuid) ||
                (u.zuid && u.zuid === user.zuid) ||
                (u.id && u.id === user.id) ||
                (u.Email && u.Email === user.Email)
              )
            );
            
            if (uniqueUsers.length > 0) {
              console.log(`[ZohoService] ✅ Found ${uniqueUsers.length} unique users from tasks and project fields (${allExtractedUsers.length - allAssignees.length} from project fields, ${allAssignees.length} from tasks)`);
              return uniqueUsers;
            }
          }
        }
        
        // If we have users from project fields but no tasks, return those
        if (allExtractedUsers.length > 0) {
          const uniqueUsers = allExtractedUsers.filter((user, index, self) => 
            index === self.findIndex((u) => 
              (u.email && u.email === user.email) ||
              (u.zpuid && u.zpuid === user.zpuid) ||
              (u.zuid && u.zuid === user.zuid) ||
              (u.id && u.id === user.id)
            )
          );
          if (uniqueUsers.length > 0) {
            console.log(`[ZohoService] ✅ Returning ${uniqueUsers.length} users extracted from project fields (no tasks found)`);
            return uniqueUsers;
          }
        }
      } catch (tasksError: any) {
        console.log(`[ZohoService] ⚠️  Error extracting from tasks: ${tasksError.message}`);
        // If we have users from project fields, return those even if tasks extraction failed
        if (allExtractedUsers.length > 0) {
          const uniqueUsers = allExtractedUsers.filter((user, index, self) => 
            index === self.findIndex((u) => 
              (u.email && u.email === user.email) ||
              (u.zpuid && u.zpuid === user.zpuid) ||
              (u.zuid && u.zuid === user.zuid) ||
              (u.id && u.id === user.id)
            )
          );
          if (uniqueUsers.length > 0) {
            console.log(`[ZohoService] ✅ Returning ${uniqueUsers.length} users extracted from project fields (tasks extraction failed)`);
            return uniqueUsers;
          }
        }
      }
      
      // If no response and no lastError, or all extraction methods failed
      if (!response && !lastError) {
        throw new Error('Failed to get project members: No response from any endpoint');
      }
      
      // If we have response but no members, and task extraction didn't return anything
      console.log(`[ZohoService] ⚠️  No members found from any source, returning empty array`);
      return [];
    } catch (error: any) {
      console.error('[ZohoService] Error fetching project members:', {
        projectId,
        portalId,
        status: error.response?.status,
        data: error.response?.data,
        message: error.message
      });
      throw new Error(
        `Failed to fetch project members: ${error.response?.data?.error?.message || error.message}`
      );
    }
  }

  /**
   * Map Zoho Project role to ASI app role
   * @param zohoProjectRole - Role from Zoho Project (e.g., "Admin", "Manager", "Employee")
   * @returns ASI role: 'admin', 'project_manager', 'lead', 'engineer', 'customer'
   */
  mapZohoProjectRoleToAppRole(zohoProjectRole: string | undefined | any): string {
    // Handle null, undefined, or non-string values
    if (!zohoProjectRole) {
      return 'engineer';
    }
    
    // If it's an object, try to extract the role name
    if (typeof zohoProjectRole === 'object') {
      const roleName = zohoProjectRole.name || 
                      zohoProjectRole.role || 
                      zohoProjectRole.designation || 
                      zohoProjectRole.value ||
                      zohoProjectRole.label ||
                      zohoProjectRole.title;
      if (roleName && typeof roleName === 'string') {
        zohoProjectRole = roleName;
      } else {
        // If we can't extract a string, default to engineer
        return 'engineer';
      }
    }
    
    // Ensure it's a string before calling toLowerCase
    if (typeof zohoProjectRole !== 'string') {
      // Try to convert to string as last resort
      zohoProjectRole = String(zohoProjectRole);
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
    
    // CAD engineer roles
    const cadEngineerKeywords = [
      'cad engineer', 'cad-engineer', 'cad', 'flow engineer'
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

    // CAD engineer (check after customer/admin/PM/lead so those override)
    if (cadEngineerKeywords.some(keyword => roleLower.includes(keyword))) {
      return 'cad_engineer';
    }
    
    // Default to engineer
    return 'engineer';
  }

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
    console.log(`[ZohoService] Starting sync for ASI project ${asiProjectId}, Zoho project ${zohoProjectId}`);
    
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN');

      // Get project members from Zoho
      console.log(`[ZohoService] Fetching members from Zoho project ${zohoProjectId}...`);
      const zohoMembers = await this.getProjectMembers(
        syncedByUserId,
        zohoProjectId,
        portalId
      );

      console.log(`[ZohoService] Found ${zohoMembers.length} members in Zoho project`);
      
      if (zohoMembers.length === 0) {
        console.warn(`[ZohoService] ⚠️  No members found in Zoho project ${zohoProjectId}. This might indicate an API issue or the project has no members.`);
      }

      let createdUsers = 0;
      let updatedAssignments = 0;
      const errors: Array<{ email: string; error: string }> = [];

      for (const member of zohoMembers) {
        try {
          const email = member.email || member.Email || member.mail;
          const name = member.name || member.Name || member.full_name || email?.split('@')[0] || 'Unknown';
          
          // Get Project Profile role (this is the role in the specific project)
          // Check multiple possible field names for project-specific role
          // The role might be an object with a 'name' property, or a string
          let projectProfileRole: any = member.project_profile || 
                                      member.project_role || 
                                      member.role_in_project ||
                                      member.role || 
                                      member.Role || 
                                      member.project_role_name ||
                                      member.designation;
          
          // If role is an object, extract the name/value
          if (projectProfileRole && typeof projectProfileRole === 'object') {
            projectProfileRole = projectProfileRole.name || 
                                projectProfileRole.role || 
                                projectProfileRole.designation || 
                                projectProfileRole.value ||
                                projectProfileRole.label ||
                                projectProfileRole.title ||
                                'Employee';
          }
          
          // Default to 'Employee' if no role found
          if (!projectProfileRole) {
            projectProfileRole = 'Employee';
          }
          
          if (!email) {
            errors.push({
              email: 'N/A',
              error: 'Member missing email address'
            });
            continue;
          }

          // Use Project Profile role for user_projects.role (project-specific role)
          // Map Zoho Project role to ASI role
          const asiRole = this.mapZohoProjectRoleToAppRole(projectProfileRole);

          // Check if user exists
          const userCheck = await client.query(
            'SELECT id, role, full_name FROM users WHERE email = $1',
            [email]
          );

          let userId: number;

          if (userCheck.rows.length === 0) {
            // Create new user (Zoho-only user)
            // Set default role to 'engineer' in users table
            // Project-specific role will be stored in user_projects.role
            
            // Generate username from email prefix, but handle conflicts
            let baseUsername = email.split('@')[0].toLowerCase();
            let username = baseUsername;
            let usernameConflict = true;
            let attempts = 0;
            const maxAttempts = 10;
            
            // Check if username already exists and generate unique one if needed
            while (usernameConflict && attempts < maxAttempts) {
              const usernameCheck = await client.query(
                'SELECT id FROM users WHERE username = $1',
                [username]
              );
              
              if (usernameCheck.rows.length === 0) {
                usernameConflict = false;
              } else {
                // Username exists, try with suffix
                attempts++;
                username = `${baseUsername}_${attempts}`;
              }
            }
            
            // If still conflict after max attempts, use email as username (sanitized)
            if (usernameConflict) {
              username = email.replace(/[^a-zA-Z0-9]/g, '_').toLowerCase();
              console.log(`[ZohoService] Username conflict after ${maxAttempts} attempts, using email-based username: ${username}`);
            }
            
            try {
              const insertResult = await client.query(
                `INSERT INTO users (
                  username, email, password_hash, full_name, role, is_active
                ) VALUES ($1, $2, $3, $4, $5, $6)
                RETURNING id`,
                [
                  username,
                  email,
                  'zoho_oauth_user',
                  name,
                  'engineer', // Default role - project-specific roles are in user_projects.role
                  true
                ]
              );
              userId = insertResult.rows[0].id;
              createdUsers++;
              console.log(`[ZohoService] ✅ Created new user: ${email} (username: ${username}, id: ${userId})`);
            } catch (insertError: any) {
              // Handle unique constraint violations
              if (insertError.code === '23505') { // Unique violation
                const constraint = insertError.constraint || 'unknown';
                console.error(`[ZohoService] ❌ Unique constraint violation for user ${email}: ${constraint}`, insertError.message);
                errors.push({
                  email,
                  error: `Username or email already exists: ${insertError.message}`
                });
                continue; // Skip this user and continue with next
              } else {
                throw insertError; // Re-throw other errors
              }
            }
          } else {
            userId = userCheck.rows[0].id;
            const existingName = userCheck.rows[0].full_name;
            
            // Update name if changed (but don't update global role - it's project-specific)
            if (name !== existingName) {
              await client.query(
                'UPDATE users SET full_name = COALESCE($1, full_name) WHERE id = $2',
                [name, userId]
              );
            }
            // Note: We don't update users.role here because:
            // - users.role is a global/default role
            // - user_projects.role is the project-specific role (handled below)
          }

          // Assign user to project with project-specific role
          try {
            // Check if user is already assigned to this project
            const existingAssignment = await client.query(
              'SELECT role FROM user_projects WHERE user_id = $1 AND project_id = $2',
              [userId, asiProjectId]
            );

            if (existingAssignment.rows.length > 0) {
              // User already assigned - check if role needs updating
              const existingRole = existingAssignment.rows[0].role;
              
              if (existingRole !== asiRole) {
                // Role has changed - update it
                console.log(`[ZohoService] Updating role for user ${email} in project ${asiProjectId}: ${existingRole} -> ${asiRole}`);
                await client.query(
                  `UPDATE user_projects 
                   SET role = $1
                   WHERE user_id = $2 AND project_id = $3`,
                  [asiRole, userId, asiProjectId]
                );
                updatedAssignments++;
              } else {
                // Role unchanged - no update needed
                console.log(`[ZohoService] User ${email} already assigned to project ${asiProjectId} with role ${asiRole} (no change)`);
              }
            } else {
              // New assignment - insert
              console.log(`[ZohoService] Assigning user ${email} to project ${asiProjectId} with role ${asiRole}`);
              await client.query(
                `INSERT INTO user_projects (user_id, project_id, role)
                 VALUES ($1, $2, $3)`,
                [userId, asiProjectId, asiRole]
              );
              updatedAssignments++;
            }
          } catch (dbError: any) {
            // If role column doesn't exist, try without it
            if (dbError.message?.includes('column "role"') || dbError.message?.includes('does not exist')) {
              console.log(`[ZohoService] Role column not found, assigning user without role`);
              const existingCheck = await client.query(
                'SELECT 1 FROM user_projects WHERE user_id = $1 AND project_id = $2',
                [userId, asiProjectId]
              );
              
              if (existingCheck.rows.length === 0) {
                await client.query(
                  `INSERT INTO user_projects (user_id, project_id)
                   VALUES ($1, $2)`,
                  [userId, asiProjectId]
                );
                updatedAssignments++;
              }
            } else {
              throw dbError;
            }
          }

        } catch (memberError: any) {
          const errorMsg = memberError.message || 'Unknown error';
          const errorCode = memberError.code || 'N/A';
          const errorDetail = memberError.detail || 'N/A';
          console.error(`[ZohoService] ❌ Error syncing member ${member.email || 'N/A'}:`, {
            message: errorMsg,
            code: errorCode,
            detail: errorDetail,
            stack: memberError.stack?.substring(0, 200)
          });
          errors.push({
            email: member.email || member.Email || member.mail || 'N/A',
            error: `${errorMsg}${errorCode !== 'N/A' ? ` (code: ${errorCode})` : ''}`
          });
        }
      }

      await client.query('COMMIT');

      console.log(`[ZohoService] Sync completed: ${createdUsers} users created, ${updatedAssignments} assignments updated, ${errors.length} errors`);

      return {
        totalMembers: zohoMembers.length,
        createdUsers,
        updatedAssignments,
        errors
      };

    } catch (error: any) {
      await client.query('ROLLBACK');
      console.error('[ZohoService] Error in syncProjectMembers, rolling back transaction:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Get tasks for a project
   * Zoho Projects organizes tasks under tasklists, so we need to:
   * 1. Get all tasklists for the project
   * 2. Get tasks from each tasklist
   * 3. Get subtasks for each task
   * 4. Include milestone information for tasklists
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
        
        // Fetch milestones to get milestone information for tasklists
        let milestones: any[] = [];
        const milestoneMap: Map<string, any> = new Map();
        try {
          milestones = await this.getMilestones(userId, correctProjectId, portal);
          console.log(`Found ${milestones.length} milestones for project ${projectId}`);
          
          // Create a map of milestone_id to milestone data for quick lookup
          for (const milestone of milestones) {
            const milestoneId = milestone.id_string || milestone.id;
            if (milestoneId) {
              milestoneMap.set(milestoneId.toString(), {
                id: milestoneId,
                name: milestone.name || milestone.milestone_name || 'Unnamed Milestone',
                start_date: milestone.start_date || milestone.start_date_format,
                end_date: milestone.end_date || milestone.end_date_format,
                status: milestone.status
              });
            }
          }
        } catch (milestoneError: any) {
          console.warn('Could not fetch milestones, continuing without milestone info:', milestoneError.message);
        }
        
        // Get tasks from each tasklist
        for (const tasklist of tasklists) {
          const tasklistId = tasklist.id_string || tasklist.id;
          const tasklistName = tasklist.name || tasklist.tasklist_name || 'Unnamed Tasklist';
          
          if (!tasklistId) {
            console.warn('Tasklist missing ID, skipping:', tasklist);
            continue;
          }
          
          // Get milestone info for this tasklist
          // Try multiple sources: tasklist.milestone object, tasklist.milestone_id, or from milestoneMap
          const tasklistMilestoneId = tasklist.milestone_id || tasklist.milestone?.id_string || tasklist.milestone?.id;
          let milestoneInfo = tasklistMilestoneId ? milestoneMap.get(tasklistMilestoneId.toString()) : null;
          
          // If milestone info not in map, try to get from tasklist.milestone object directly
          if (!milestoneInfo && tasklist.milestone) {
            const tasklistMilestone = tasklist.milestone;
            milestoneInfo = {
              id: tasklistMilestone.id_string || tasklistMilestone.id || tasklistMilestoneId,
              name: tasklistMilestone.name || tasklistMilestone.milestone_name || 'Unnamed Milestone',
              start_date: tasklistMilestone.start_date || tasklistMilestone.start_date_format,
              end_date: tasklistMilestone.end_date || tasklistMilestone.end_date_format,
              status: tasklistMilestone.status
            };
            // Also add to map for future use
            if (tasklistMilestoneId) {
              milestoneMap.set(tasklistMilestoneId.toString(), milestoneInfo);
            }
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
            
            // Helper function to extract owner information from task
            const extractOwnerInfo = (taskItem: any): { owner_name?: string; owner_role?: string } => {
              let ownerName: string | undefined;
              let ownerRole: string | undefined;
              
              // Try to extract from owners_and_work field (V3 API format)
              if (taskItem.owners_and_work) {
                if (Array.isArray(taskItem.owners_and_work) && taskItem.owners_and_work.length > 0) {
                  const ownerWork = taskItem.owners_and_work[0];
                  const owner = ownerWork?.owner || ownerWork;
                  if (owner) {
                    ownerName = owner.name || `${owner.first_name || ''} ${owner.last_name || ''}`.trim() || undefined;
                    ownerRole = owner.role || ownerWork?.role || undefined;
                  }
                } else if (typeof taskItem.owners_and_work === 'object') {
                  const owner = taskItem.owners_and_work.owner || taskItem.owners_and_work;
                  if (owner) {
                    ownerName = owner.name || `${owner.first_name || ''} ${owner.last_name || ''}`.trim() || undefined;
                    ownerRole = owner.role || undefined;
                  }
                }
              }
              
              // Fallback to owner fields
              if (!ownerName && taskItem.owner) {
                if (typeof taskItem.owner === 'object') {
                  ownerName = taskItem.owner.name || `${taskItem.owner.first_name || ''} ${taskItem.owner.last_name || ''}`.trim() || undefined;
                  ownerRole = taskItem.owner.role || undefined;
                } else {
                  ownerName = taskItem.owner;
                }
              }
              
              // Fallback to owner_name field
              if (!ownerName && taskItem.owner_name) {
                ownerName = taskItem.owner_name;
                ownerRole = taskItem.owner_role || undefined;
              }
              
              return {
                owner_name: ownerName,
                owner_role: ownerRole
              };
            };
            
            // Add tasklist info and milestone info to each task
            // Try to get milestone info from task itself if milestone API failed
            tasks = tasks.map(task => {
              // Get milestone ID from task if tasklist doesn't have it
              const taskMilestoneId = task.milestone_id || tasklistMilestoneId;
              let finalMilestoneInfo = milestoneInfo;
              
              // If we don't have milestone info from API but task has milestone_id, try to get from map
              if (!finalMilestoneInfo && taskMilestoneId) {
                finalMilestoneInfo = milestoneMap.get(taskMilestoneId.toString());
              }
              
              // If still no milestone info, check if task has milestone data embedded
              if (!finalMilestoneInfo && task.milestone) {
                const taskMilestone = task.milestone;
                finalMilestoneInfo = {
                  id: taskMilestone.id_string || taskMilestone.id || taskMilestoneId,
                  name: taskMilestone.name || taskMilestone.milestone_name || 'Unnamed Milestone',
                  start_date: taskMilestone.start_date || taskMilestone.start_date_format,
                  end_date: taskMilestone.end_date || taskMilestone.end_date_format
                };
              }
              
              // Extract owner information
              const ownerInfo = extractOwnerInfo(task);
              
              // Return task with all original fields plus additional metadata
              // Using spread operator first to include ALL original task fields
              return {
                ...task, // Include ALL original task fields from Zoho API
                // Explicitly include common fields to ensure they're present
                id: task.id || task.id_string,
                id_string: task.id_string || task.id,
                name: task.name || task.task_name,
                task_name: task.task_name || task.name,
                description: task.description || task.details?.description || task.details,
                status: task.status || task.status_detail?.status,
                start_date: task.start_date || task.start_date_format,
                end_date: task.end_date || task.end_date_format,
                created_date: task.created_date || task.created_date_format,
                updated_date: task.updated_date || task.updated_date_format,
                priority: task.priority,
                percent_complete: task.percent_complete || task.completion_percentage,
                owner: task.owner,
                assignee: task.assignee,
                details: task.details,
                link: task.link,
                // Additional metadata fields
                tasklist_id: tasklistId,
                tasklist_name: tasklistName,
                milestone_id: taskMilestoneId || null,
                milestone_name: finalMilestoneInfo?.name || null,
                milestone_start_date: finalMilestoneInfo?.start_date || null,
                milestone_end_date: finalMilestoneInfo?.end_date || null,
                // Also add milestone info at tasklist level for easier grouping
                tasklist_milestone: finalMilestoneInfo ? {
                  id: finalMilestoneInfo.id,
                  name: finalMilestoneInfo.name,
                  start_date: finalMilestoneInfo.start_date,
                  end_date: finalMilestoneInfo.end_date
                } : null,
                // Add owner information
                owner_name: ownerInfo.owner_name,
                owner_role: ownerInfo.owner_role
              };
            });
            
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
            
            // Helper function to extract owner information (reuse from above scope)
            const extractOwnerInfo = (taskItem: any): { owner_name?: string; owner_role?: string } => {
              let ownerName: string | undefined;
              let ownerRole: string | undefined;
              
              // Try to extract from owners_and_work field (V3 API format)
              if (taskItem.owners_and_work) {
                if (Array.isArray(taskItem.owners_and_work) && taskItem.owners_and_work.length > 0) {
                  const ownerWork = taskItem.owners_and_work[0];
                  const owner = ownerWork?.owner || ownerWork;
                  if (owner) {
                    ownerName = owner.name || `${owner.first_name || ''} ${owner.last_name || ''}`.trim() || undefined;
                    ownerRole = owner.role || ownerWork?.role || undefined;
                  }
                } else if (typeof taskItem.owners_and_work === 'object') {
                  const owner = taskItem.owners_and_work.owner || taskItem.owners_and_work;
                  if (owner) {
                    ownerName = owner.name || `${owner.first_name || ''} ${owner.last_name || ''}`.trim() || undefined;
                    ownerRole = owner.role || undefined;
                  }
                }
              }
              
              // Fallback to owner fields
              if (!ownerName && taskItem.owner) {
                if (typeof taskItem.owner === 'object') {
                  ownerName = taskItem.owner.name || `${taskItem.owner.first_name || ''} ${taskItem.owner.last_name || ''}`.trim() || undefined;
                  ownerRole = taskItem.owner.role || undefined;
                } else {
                  ownerName = taskItem.owner;
                }
              }
              
              // Fallback to owner_name field
              if (!ownerName && taskItem.owner_name) {
                ownerName = taskItem.owner_name;
                ownerRole = taskItem.owner_role || undefined;
              }
              
              return {
                owner_name: ownerName,
                owner_role: ownerRole
              };
            };
            
            // Extract owner information for the main task
            const taskOwnerInfo = extractOwnerInfo(task);
            
            // Add owner information to subtasks
            const subtasksWithOwner = (subtasks || []).map((subtask: any) => {
              const ownerInfo = extractOwnerInfo(subtask);
              return {
                ...subtask,
                owner_name: ownerInfo.owner_name,
                owner_role: ownerInfo.owner_role
              };
            });
            
            // Ensure all task fields are included in the response
            return {
              ...task, // Include all original task fields
              // Explicitly include common task fields to ensure they're present
              id: task.id || task.id_string,
              id_string: task.id_string || task.id,
              name: task.name || task.task_name,
              task_name: task.task_name || task.name,
              description: task.description || task.details?.description || task.details,
              status: task.status || task.status_detail?.status,
              start_date: task.start_date || task.start_date_format,
              end_date: task.end_date || task.end_date_format,
              created_date: task.created_date || task.created_date_format,
              updated_date: task.updated_date || task.updated_date_format,
              priority: task.priority,
              percent_complete: task.percent_complete || task.completion_percentage,
              owner: task.owner,
              assignee: task.assignee,
              details: task.details,
              link: task.link,
              // Explicitly include owner_name and owner_role extracted from the task
              owner_name: taskOwnerInfo.owner_name || task.owner_name,
              owner_role: taskOwnerInfo.owner_role || task.owner_role,
              subtasks: subtasksWithOwner
            };
          } catch (subtaskError: any) {
            // Helper function to extract owner information (reuse from above scope)
            const extractOwnerInfo = (taskItem: any): { owner_name?: string; owner_role?: string } => {
              let ownerName: string | undefined;
              let ownerRole: string | undefined;
              
              // Try to extract from owners_and_work field (V3 API format)
              if (taskItem.owners_and_work) {
                if (Array.isArray(taskItem.owners_and_work) && taskItem.owners_and_work.length > 0) {
                  const ownerWork = taskItem.owners_and_work[0];
                  const owner = ownerWork?.owner || ownerWork;
                  if (owner) {
                    ownerName = owner.name || `${owner.first_name || ''} ${owner.last_name || ''}`.trim() || undefined;
                    ownerRole = owner.role || ownerWork?.role || undefined;
                  }
                } else if (typeof taskItem.owners_and_work === 'object') {
                  const owner = taskItem.owners_and_work.owner || taskItem.owners_and_work;
                  if (owner) {
                    ownerName = owner.name || `${owner.first_name || ''} ${owner.last_name || ''}`.trim() || undefined;
                    ownerRole = owner.role || undefined;
                  }
                }
              }
              
              // Fallback to owner fields
              if (!ownerName && taskItem.owner) {
                if (typeof taskItem.owner === 'object') {
                  ownerName = taskItem.owner.name || `${taskItem.owner.first_name || ''} ${taskItem.owner.last_name || ''}`.trim() || undefined;
                  ownerRole = taskItem.owner.role || undefined;
                } else {
                  ownerName = taskItem.owner;
                }
              }
              
              // Fallback to owner_name field
              if (!ownerName && taskItem.owner_name) {
                ownerName = taskItem.owner_name;
                ownerRole = taskItem.owner_role || undefined;
              }
              
              return {
                owner_name: ownerName,
                owner_role: ownerRole
              };
            };
            
            // Extract owner information for the main task
            const taskOwnerInfo = extractOwnerInfo(task);
            
            // If subtasks endpoint fails, check if task already has subtasks embedded
            if (task.subtasks && Array.isArray(task.subtasks) && task.subtasks.length > 0) {
              console.log(`✅ Using embedded subtasks for task ${task.id_string || task.id} (${task.subtasks.length} subtasks)`);
              // Add owner information to embedded subtasks
              const subtasksWithOwner = task.subtasks.map((subtask: any) => {
                const ownerInfo = extractOwnerInfo(subtask);
                return {
                  ...subtask,
                  owner_name: ownerInfo.owner_name,
                  owner_role: ownerInfo.owner_role
                };
              });
              return {
                ...task,
                owner_name: taskOwnerInfo.owner_name || task.owner_name,
                owner_role: taskOwnerInfo.owner_role || task.owner_role,
                subtasks: subtasksWithOwner
              };
            }
            
            // If subtasks endpoint fails, just return task without subtasks
            console.warn(`Failed to fetch subtasks for task ${task.id_string || task.id}:`, subtaskError.response?.data?.error?.message || subtaskError.message);
            return {
              ...task,
              owner_name: taskOwnerInfo.owner_name || task.owner_name,
              owner_role: taskOwnerInfo.owner_role || task.owner_role,
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
    
    // Verify user exists before saving tokens
    const userCheck = await pool.query(
      'SELECT id, username, email FROM public.users WHERE id = $1',
      [userId]
    );
    
    if (userCheck.rows.length === 0) {
      console.error(`[SAVE_TOKENS] ERROR: User ${userId} does not exist in users table`);
      throw new Error(`Cannot save tokens: User with ID ${userId} does not exist. Please ensure the user is created first.`);
    }
    
    console.log(`[SAVE_TOKENS] Verified user exists: ${userCheck.rows[0].username} (${userCheck.rows[0].email})`);
    
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
      `INSERT INTO public.zoho_tokens 
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
      'SELECT id, user_id, expires_at FROM public.zoho_tokens WHERE user_id = $1',
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
        'SELECT expires_at FROM public.zoho_tokens WHERE user_id = $1',
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
    await pool.query('DELETE FROM public.zoho_tokens WHERE user_id = $1', [userId]);
  }

  /**
   * Get milestones for a project
   */
  async getMilestones(userId: number, projectId: string, portalId?: string): Promise<any[]> {
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

      // Try different endpoint variations for milestones
      const endpointVariations = [
        `/restapi/portal/${portal}/projects/${projectId}/milestones/`,
        `/restapi/v3/portal/${portal}/projects/${projectId}/milestones/`,
        `/portal/${portal}/projects/${projectId}/milestones/`,
      ];

      let milestones: any[] = [];
      
      for (const endpoint of endpointVariations) {
        try {
          const response = await client.get(endpoint);
          
          if (response.data.response?.result?.milestones) {
            milestones = response.data.response.result.milestones;
          } else if (response.data.milestones) {
            milestones = response.data.milestones;
          } else if (Array.isArray(response.data)) {
            milestones = response.data;
          }
          
          if (milestones.length > 0) {
            console.log(`✅ Found ${milestones.length} milestones via ${endpoint}`);
            break;
          }
        } catch (error: any) {
          // Continue to next variation
          continue;
        }
      }

      return milestones;
    } catch (error: any) {
      console.error('Error fetching milestones:', error.response?.data || error.message);
      return [];
    }
  }

  /**
   * Get bugs/tickets for a project
   */
  async getBugs(userId: number, projectId: string, portalId?: string): Promise<any[]> {
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

      console.log('[getBugs] Using portal:', { id: portal, name: portalName });

      // First, get the project to find the correct project ID (id_string)
      let correctProjectId = projectId;
      let project: any = null;

      try {
        // Try different endpoint formats for getting project
        const projectEndpointVariations = [];
        
        if (portalName) {
          projectEndpointVariations.push({
            name: 'portal name',
            url: `/restapi/portal/${portalName}/projects/${projectId}/`
          });
        }
        
        projectEndpointVariations.push({
          name: 'portal ID',
          url: `/restapi/portal/${portal}/projects/${projectId}/`
        });
        
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
            console.log(`[getBugs] Trying project endpoint: ${variation.name} - ${variation.url}`);
            const projectResponse = await client.get(variation.url);
            project = projectResponse.data.response?.result || projectResponse.data;
            console.log('[getBugs] ✅ Project fetched successfully via', variation.name);
            projectFetchSuccess = true;
            break;
          } catch (projectError: any) {
            console.log(`[getBugs] ❌ Project endpoint ${variation.name} failed:`, projectError.response?.data?.error?.message || projectError.message);
            // Continue to next variation
          }
        }
        
        // If all project endpoints failed, try getting from projects list
        if (!projectFetchSuccess) {
          console.log('[getBugs] ⚠️  Single project endpoint failed, trying to get from projects list...');
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
              console.log('[getBugs] ✅ Found project in projects list');
              projectFetchSuccess = true;
            }
          } catch (listError: any) {
            console.error('[getBugs] ❌ Failed to get projects list:', listError.response?.data?.error?.message || listError.message);
          }
        }
        
        if (project) {
          // Use the correct project ID - prefer id_string over id (as seen in link URLs)
          correctProjectId = project.id_string || projectId;
          console.log(`[getBugs] 🔑 Using project ID: ${correctProjectId} (original: ${projectId}, id_string: ${project?.id_string})`);
          
          // Log project link structure for debugging
          if (project.link) {
            console.log(`[getBugs] Project link keys:`, Object.keys(project.link));
            if (project.link.bug) {
              console.log(`[getBugs] Project link.bug:`, project.link.bug);
            } else {
              console.log(`[getBugs] ⚠️  No 'bug' key in project.link. Available keys:`, Object.keys(project.link));
            }
          } else {
            console.log(`[getBugs] ⚠️  No 'link' object in project`);
          }
        }
      } catch (projectError: any) {
        console.warn('[getBugs] Could not fetch project, using original projectId:', projectError.message);
        // Continue with original projectId
      }

      // Try different endpoint variations for bugs using the correct project ID
      const endpointVariations = [];
      
      // First: Try using the link URL from project object if available (MOST RELIABLE)
      if (project?.link?.bug?.url) {
        const bugUrl = project.link.bug.url;
        // Remove base URL to get just the path
        const bugPath = bugUrl
          .replace('https://projectsapi.zoho.in', '')
          .replace('https://projectsapi.zoho.com', '')
          .replace('https://projectsapi.zoho.eu', '')
          .replace('https://projectsapi.zoho.com.au', '');
        endpointVariations.push({
          name: 'project.link.bug URL (CORRECT)',
          url: bugPath
        });
        console.log(`[getBugs] Found bug link URL in project: ${bugUrl} -> ${bugPath}`);
      } else {
        console.log('[getBugs] ⚠️  No bug link URL found in project.link.bug.url');
        console.log('[getBugs] Project link keys:', project?.link ? Object.keys(project.link) : 'No link object');
      }
      
      // Try with "issues" instead of "bugs" (some Zoho setups use "issues")
      if (correctProjectId !== projectId) {
        endpointVariations.push({
          name: 'portal ID with id_string (issues)',
          url: `/restapi/portal/${portal}/projects/${correctProjectId}/issues/`
        });
      }
      
      // Try with portal name using "issues"
      if (portalName) {
        endpointVariations.push({
          name: 'portal name with /restapi/ (issues)',
          url: `/restapi/portal/${portalName}/projects/${correctProjectId}/issues/`
        });
      }
      
      // Try with portal ID using id_string and "issues"
      endpointVariations.push({
        name: 'portal ID with /restapi/ (id_string, issues)',
        url: `/restapi/portal/${portal}/projects/${correctProjectId}/issues/`
      });
      
      // Try with id_string (the correct project ID) - bugs endpoint
      if (correctProjectId !== projectId) {
        endpointVariations.push({
          name: 'portal ID with id_string (bugs)',
          url: `/restapi/portal/${portal}/projects/${correctProjectId}/bugs/`
        });
      }
      
      // Try with portal name
      if (portalName) {
        endpointVariations.push({
          name: 'portal name with /restapi/ (bugs)',
          url: `/restapi/portal/${portalName}/projects/${correctProjectId}/bugs/`
        });
        endpointVariations.push({
          name: 'portal name without /restapi/ (bugs)',
          url: `/portal/${portalName}/projects/${correctProjectId}/bugs/`
        });
      }
      
      // Try with portal ID using id_string
      endpointVariations.push({
        name: 'portal ID with /restapi/ (id_string, bugs)',
        url: `/restapi/portal/${portal}/projects/${correctProjectId}/bugs/`
      });
      endpointVariations.push({
        name: 'portal ID without /restapi/ (id_string, bugs)',
        url: `/portal/${portal}/projects/${correctProjectId}/bugs/`
      });
      
      // Try with original projectId as fallback
      endpointVariations.push({
        name: 'portal ID with /restapi/ (original id, bugs)',
        url: `/restapi/portal/${portal}/projects/${projectId}/bugs/`
      });
      
      // Try with API versions using id_string
      endpointVariations.push({
        name: 'v3 API with portal ID (id_string, bugs)',
        url: `/restapi/v3/portal/${portal}/projects/${correctProjectId}/bugs/`
      });
      endpointVariations.push({
        name: 'v1 API with portal ID (id_string, bugs)',
        url: `/restapi/v1/portal/${portal}/projects/${correctProjectId}/bugs/`
      });

      let bugs: any[] = [];
      
      for (const variation of endpointVariations) {
        if (bugs.length > 0) break; // Stop if we found bugs
        
        try {
          console.log(`[getBugs] Trying bugs endpoint: ${variation.name} - ${variation.url}`);
          const response = await client.get(variation.url);
          
          // Try multiple response structures - bugs, issues, tickets
          if (response.data.response?.result?.bugs) {
            bugs = response.data.response.result.bugs;
          } else if (response.data.response?.result?.issues) {
            bugs = response.data.response.result.issues;
          } else if (response.data.response?.result?.tickets) {
            bugs = response.data.response.result.tickets;
          } else if (response.data.bugs) {
            bugs = response.data.bugs;
          } else if (response.data.issues) {
            bugs = response.data.issues;
          } else if (response.data.tickets) {
            bugs = response.data.tickets;
          } else if (Array.isArray(response.data)) {
            bugs = response.data;
          } else if (response.data.response?.result && Array.isArray(response.data.response.result)) {
            bugs = response.data.response.result;
          }
          
          if (bugs.length > 0) {
            console.log(`[getBugs] ✅ Found ${bugs.length} bugs/issues/tickets via ${variation.name}`);
            console.log(`[getBugs] Sample bug data keys:`, bugs[0] ? Object.keys(bugs[0]) : 'No bugs');
            break;
          } else {
            console.log(`[getBugs] ⚠️  ${variation.name} returned empty array. Response structure:`, {
              hasResponse: !!response.data.response,
              hasResult: !!response.data.response?.result,
              resultKeys: response.data.response?.result ? Object.keys(response.data.response.result) : [],
              topLevelKeys: Object.keys(response.data || {})
            });
          }
        } catch (error: any) {
          const errorMsg = error.response?.data?.error?.message || error.message;
          const errorCode = error.response?.data?.error?.code;
          console.log(`[getBugs] ❌ ${variation.name} failed: ${errorMsg}${errorCode ? ` (code: ${errorCode})` : ''}`);
          if (error.response?.data) {
            console.log(`[getBugs] Error response data:`, JSON.stringify(error.response.data).substring(0, 200));
          }
          // Continue to next variation
          continue;
        }
      }

      if (bugs.length === 0) {
        console.warn('[getBugs] ⚠️  No bugs found after trying all endpoint variations');
      }

      return bugs;
    } catch (error: any) {
      console.error('[getBugs] Error fetching bugs/tickets:', error.response?.data || error.message);
      return [];
    }
  }

  /**
   * Get project status for management view
   * Fetches comprehensive project data from Zoho including milestones, tickets, tasks, and project details
   */
  async getProjectManagementStatus(userId: number, zohoProjectId: string, portalId?: string): Promise<{
    project_details: {
      name: string;
      status: string;
      start_date?: string;
      end_date?: string;
      owner_name?: string;
      progress_percentage?: number;
      description?: string;
    };
    rtl: { current_stage: string; milestone_status: { overdue: number; pending: number; total: number } };
    dv: { current_stage: string; milestone_status: { overdue: number; pending: number; total: number } };
    pd: { current_stage: string; milestone_status: { overdue: number; pending: number; total: number } };
    al: { current_stage: string; milestone_status: { overdue: number; pending: number; total: number } };
    dft: { current_stage: string; milestone_status: { overdue: number; pending: number; total: number } };
    tickets: { pending: number; total: number; open: number; closed: number };
    tasks: { total: number; open: number; closed: number };
    milestones_by_stage: { [key: string]: { overdue: number; pending: number; total: number } };
  }> {
    try {
      // Get comprehensive project data
      const project = await this.getProject(userId, zohoProjectId, portalId);
      const milestones = await this.getMilestones(userId, zohoProjectId, portalId);
      const bugs = await this.getBugs(userId, zohoProjectId, portalId);
      const tasks = await this.getTasks(userId, zohoProjectId, portalId);

      // Extract project details
      const projectDetails = {
        name: project.name || 'N/A',
        status: project.status || project.custom_status_name || 'N/A',
        start_date: project.start_date || project.start_date_format || undefined,
        end_date: project.end_date || project.end_date_format || undefined,
        owner_name: project.owner_name || project.owner?.name || undefined,
        progress_percentage: project.project_percent || 0,
        description: project.description || undefined,
      };

      // Calculate milestone status by stage
      // Group milestones by stage name (RTL, DV, PD, AL, DFT)
      const now = new Date();
      const milestonesByStage: { [key: string]: { overdue: number; pending: number; total: number } } = {
        rtl: { overdue: 0, pending: 0, total: 0 },
        dv: { overdue: 0, pending: 0, total: 0 },
        pd: { overdue: 0, pending: 0, total: 0 },
        al: { overdue: 0, pending: 0, total: 0 },
        dft: { overdue: 0, pending: 0, total: 0 },
      };

      milestones.forEach((milestone: any) => {
        const milestoneName = (milestone.name || milestone.milestone_name || '').toLowerCase();
        const endDate = milestone.end_date || milestone.due_date || milestone.target_date || milestone.end_date_long;
        const isCompleted = milestone.status === 'completed' || milestone.status === 'closed' || milestone.completed || milestone.status_name === 'Completed';
        
        // Determine stage from milestone name
        let stage = 'rtl'; // default
        if (milestoneName.includes('dv') || milestoneName.includes('design verification')) {
          stage = 'dv';
        } else if (milestoneName.includes('pd') || milestoneName.includes('physical design')) {
          stage = 'pd';
        } else if (milestoneName.includes('al') || milestoneName.includes('analog')) {
          stage = 'al';
        } else if (milestoneName.includes('dft') || milestoneName.includes('design for test')) {
          stage = 'dft';
        } else if (milestoneName.includes('rtl') || milestoneName.includes('register transfer')) {
          stage = 'rtl';
        }

        milestonesByStage[stage].total++;
        
        if (!isCompleted) {
          if (endDate) {
            let dueDate: Date;
            if (typeof endDate === 'number') {
              dueDate = new Date(endDate);
            } else {
              dueDate = new Date(endDate);
            }
            
            if (dueDate < now) {
              milestonesByStage[stage].overdue++;
            } else {
              milestonesByStage[stage].pending++;
            }
          } else {
            milestonesByStage[stage].pending++;
          }
        }
      });

      // Get current stage from project custom fields or tasklists
      // For now, use a placeholder that can be enhanced later
      const getCurrentStage = (stageName: string): string => {
        // Try to get from custom fields or tasklists
        const customFields = project.custom_fields || [];
        const stageField = customFields.find((field: any) => 
          field[stageName.toUpperCase()] || field[`${stageName}_stage`]
        );
        
        if (stageField) {
          return stageField[stageName.toUpperCase()] || stageField[`${stageName}_stage`] || 'bronze/silver/gold';
        }
        
        // Default based on progress
        const progress = projectDetails.progress_percentage || 0;
        if (progress < 33) return 'bronze';
        if (progress < 66) return 'silver';
        return 'gold';
      };

      // Count bugs/tickets
      const totalBugs = bugs.length;
      const openBugs = bugs.filter((bug: any) => {
        const status = (bug.status?.toLowerCase() || bug.status_name?.toLowerCase() || '');
        return status !== 'closed' && status !== 'resolved' && status !== 'fixed';
      }).length;
      const closedBugs = totalBugs - openBugs;

      // Count tasks
      const totalTasks = tasks.length;
      const openTasks = tasks.filter((task: any) => {
        const status = (task.status?.toLowerCase() || task.status_name?.toLowerCase() || '');
        return status !== 'closed' && status !== 'completed';
      }).length;
      const closedTasks = totalTasks - openTasks;

      return {
        project_details: projectDetails,
        rtl: {
          current_stage: getCurrentStage('rtl'),
          milestone_status: milestonesByStage.rtl
        },
        dv: {
          current_stage: getCurrentStage('dv'),
          milestone_status: milestonesByStage.dv
        },
        pd: {
          current_stage: getCurrentStage('pd'),
          milestone_status: milestonesByStage.pd
        },
        al: {
          current_stage: getCurrentStage('al'),
          milestone_status: milestonesByStage.al
        },
        dft: {
          current_stage: getCurrentStage('dft'),
          milestone_status: milestonesByStage.dft
        },
        tickets: {
          pending: openBugs,
          total: totalBugs,
          open: openBugs,
          closed: closedBugs
        },
        tasks: {
          total: totalTasks,
          open: openTasks,
          closed: closedTasks
        },
        milestones_by_stage: milestonesByStage
      };
    } catch (error: any) {
      console.error('Error getting project management status:', error);
      // Return default values on error
      const defaultStatus = {
        overdue: 0,
        pending: 0,
        total: 0
      };
      return {
        project_details: {
          name: 'N/A',
          status: 'N/A',
          progress_percentage: 0
        },
        rtl: { current_stage: 'N/A', milestone_status: defaultStatus },
        dv: { current_stage: 'N/A', milestone_status: defaultStatus },
        pd: { current_stage: 'N/A', milestone_status: defaultStatus },
        al: { current_stage: 'N/A', milestone_status: defaultStatus },
        dft: { current_stage: 'N/A', milestone_status: defaultStatus },
        tickets: { pending: 0, total: 0, open: 0, closed: 0 },
        tasks: { total: 0, open: 0, closed: 0 },
        milestones_by_stage: {
          rtl: defaultStatus,
          dv: defaultStatus,
          pd: defaultStatus,
          al: defaultStatus,
          dft: defaultStatus
        }
      };
    }
  }
}

export default new ZohoService();

