import { Request, Response, NextFunction } from 'express';

/**
 * API Key Authentication Middleware
 * Validates API key from X-API-Key header or api_key query parameter
 */
export const authenticateApiKey = (req: Request, res: Response, next: NextFunction) => {
  try {
    // Get API key from header (preferred) or query parameter
    const apiKey = req.headers['x-api-key'] as string || req.query.api_key as string;

    if (!apiKey) {
      return res.status(401).json({
        error: 'API key required',
        message: 'Please provide an API key using X-API-Key header or api_key query parameter',
        example: {
          header: 'X-API-Key: your-api-key-here',
          query: '?api_key=your-api-key-here'
        }
      });
    }

    // Get valid API keys from environment variable (comma-separated)
    const validApiKeys = (process.env.EDA_API_KEYS || '').split(',').map(k => k.trim()).filter(k => k.length > 0);

    if (validApiKeys.length === 0) {
      console.error('⚠️  No API keys configured. Set EDA_API_KEYS environment variable.');
      return res.status(500).json({
        error: 'API key authentication not configured',
        message: 'Server configuration error. Please contact administrator.'
      });
    }

    // Validate API key
    if (!validApiKeys.includes(apiKey)) {
      return res.status(401).json({
        error: 'Invalid API key',
        message: 'The provided API key is not valid'
      });
    }

    // API key is valid, proceed
    next();
  } catch (error: any) {
    console.error('API key authentication error:', error);
    return res.status(500).json({
      error: 'Authentication error',
      message: error.message
    });
  }
};

