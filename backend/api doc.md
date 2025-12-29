# Postman Quick Test Guide

## Your API Configuration

Based on your `.env` file:
- **API Key**: `sitedafilesdata`
- **Base URL**: `https://13.204.252.101:3000`

---

## Manual Setup (If Not Using Import)

### Request Configuration

**Method**: `POST`

**URL**: 
```
http://13.204.252.101:3000/api/eda-files/external/upload
```

### Headers Tab

Add this header:

| Key | Value |
|-----|-------|
| `X-API-Key` | `sitedafilesdata` |

### Body Tab

1. Select **form-data** (NOT raw)
2. Add field:
   - **Key**: `file`
   - **Type**: Change to **File** (dropdown on right)
   - **Value**: Click **Select Files** and choose your file

---

