# Admin Login Credentials

## Admin User Created

A new admin user has been added to the database:

- **Username**: `admin1`
- **Email**: `admin@1.com`
- **Password**: `test@1234`
- **Role**: `admin`

## Login Methods

You can login using either the username or email:

### Using Username
```bash
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin1",
    "password": "test@1234"
  }'
```

### Using Email
```bash
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@1.com",
    "password": "test@1234"
  }'
```

## Response

On successful login, you'll receive:

```json
{
  "message": "Login successful",
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": 6,
    "username": "admin1",
    "email": "admin@1.com",
    "full_name": "Admin User",
    "role": "admin"
  }
}
```

## Using the Token

Include the token in subsequent API requests:

```bash
curl -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  http://localhost:3000/api/chips
```

## SQL Script

The user was created using the SQL script:
- `backend/migrations/003_add_admin_user.sql`

This migration will automatically run when setting up a fresh database.

## Security Note

⚠️ **Change this password in production!** The default password `test@1234` should be updated for security.

