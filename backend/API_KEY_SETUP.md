# API Key Setup for External API

## Overview

The External API uses API key authentication. This document explains how to configure API keys for external developers.

## Configuration

### Environment Variable

API keys are configured using the `EDA_API_KEYS` environment variable in your `.env` file.

### Setting Up API Keys

1. **Open your `.env` file** in the `backend` directory

2. **Add the API keys** (comma-separated):

```bash
# External API Keys for EDA file uploads
# Multiple keys can be provided, separated by commas
EDA_API_KEYS=key1-abc123,key2-def456,key3-ghi789
```

3. **Restart your server** for changes to take effect

### Example `.env` File

```bash
# Database
DATABASE_URL=postgresql://postgres:root@localhost:5432/ASI

# JWT
JWT_SECRET=your-secret-key-change-in-production
JWT_EXPIRES_IN=7d

# Server
PORT=3000
NODE_ENV=development

# External API Keys
EDA_API_KEYS=dev-key-12345,prod-key-67890,test-key-abcde
```

## Generating API Keys

### Recommended Format

Use a secure, random string for each API key. Recommended length: 32-64 characters.

### Example Generation Methods

#### Using OpenSSL (Linux/Mac)
```bash
openssl rand -hex 32
```

#### Using PowerShell (Windows)
```powershell
-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object {[char]$_})
```

#### Using Python
```python
import secrets
api_key = secrets.token_urlsafe(32)
print(api_key)
```

#### Using Node.js
```javascript
const crypto = require('crypto');
const apiKey = crypto.randomBytes(32).toString('hex');
console.log(apiKey);
```

## Best Practices

1. **Use Different Keys for Different Environments**
   - Development: `dev-key-...`
   - Staging: `staging-key-...`
   - Production: `prod-key-...`

2. **Rotate Keys Periodically**
   - Change keys every 90 days or as per your security policy
   - When rotating, update the environment variable and notify developers

3. **Keep Keys Secure**
   - Never commit API keys to version control
   - Use environment variables or secrets management systems
   - Restrict access to `.env` files

4. **Monitor Usage**
   - Log API key usage for security monitoring
   - Revoke keys immediately if compromised

5. **Key Naming**
   - Use descriptive names in comments (not in the key itself)
   - Example: `# Developer 1: key1-abc123`

## Distribution

### Sharing API Keys with Developers

1. **Share keys securely** (use encrypted channels)
2. **Provide documentation** (share `EXTERNAL_API_DOCUMENTATION.md`)
3. **Include example code** (share example scripts)
4. **Set expectations** (rate limits, file size limits, etc.)

### Example Email Template

```
Subject: API Key for ASI Dashboard External API

Hello [Developer Name],

Your API key for the ASI Dashboard External API has been generated:

API Key: [API_KEY_HERE]

Server URL: https://your-server.com

Please see the attached documentation for:
- API endpoint details
- Request/response formats
- Example code
- Error handling

Keep this key secure and do not share it publicly.

Best regards,
[Your Name]
```

## Revoking API Keys

To revoke an API key:

1. **Remove it from `EDA_API_KEYS`** in your `.env` file
2. **Restart the server**
3. **Notify the developer** that their key has been revoked

## Troubleshooting

### "API key authentication not configured"

**Cause**: `EDA_API_KEYS` environment variable is not set or is empty.

**Solution**: Add `EDA_API_KEYS` to your `.env` file with at least one key.

### "Invalid API key"

**Cause**: The API key provided doesn't match any key in `EDA_API_KEYS`.

**Solution**: 
- Verify the key is correct (no extra spaces, correct format)
- Check that `EDA_API_KEYS` includes the key
- Restart the server after updating `.env`

### Keys Not Working After Update

**Cause**: Server wasn't restarted after updating `.env`.

**Solution**: Restart the backend server to load new environment variables.

## Security Considerations

1. **HTTPS**: Always use HTTPS in production to protect API keys in transit
2. **Key Storage**: Store keys securely, never in code or public repositories
3. **Access Control**: Limit who has access to API keys
4. **Monitoring**: Monitor for unusual API usage patterns
5. **Expiration**: Consider implementing key expiration if needed

## Production Deployment

### Docker

Add to `docker-compose.yml`:

```yaml
services:
  backend:
    environment:
      - EDA_API_KEYS=${EDA_API_KEYS}
```

Or use a `.env` file that's not committed to git.

### Kubernetes

Add to `backend-secret.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: backend-secret
type: Opaque
stringData:
  EDA_API_KEYS: "key1-abc123,key2-def456"
```

Then reference in deployment:

```yaml
env:
  - name: EDA_API_KEYS
    valueFrom:
      secretKeyRef:
        name: backend-secret
        key: EDA_API_KEYS
```

### EC2 / Linux Server

Add to systemd service file:

```ini
[Service]
Environment="EDA_API_KEYS=key1-abc123,key2-def456"
```

Or export in shell:

```bash
export EDA_API_KEYS="key1-abc123,key2-def456"
```

## Support

For questions or issues with API key configuration, contact your system administrator.

