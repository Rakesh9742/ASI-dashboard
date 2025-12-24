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
    this.redirectUri = process.env.ZOHO_REDIRECT_URI || '';
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
      console.error('⚠️  WARNING: ZOHO_REDIRECT_URI is not set in environment variables');
    }
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
      try {
        const crmResponse = await axios.get(
          `https://www.zohoapis.in/crm/v2/users`,
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
   * Save or update tokens for a user
   */
  async saveTokens(userId: number, tokenData: ZohoTokenResponse): Promise<void> {
    // Validate required fields
    if (!tokenData.access_token || tokenData.access_token.trim() === '') {
      throw new Error('Cannot save tokens: access_token is missing, null, or empty');
    }

    if (!tokenData.refresh_token || tokenData.refresh_token.trim() === '') {
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

    await pool.query(
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
         updated_at = CURRENT_TIMESTAMP`,
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

