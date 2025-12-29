# External API - Quick Start Guide

## Quick Reference

**Endpoint**: `POST /api/eda-files/external/upload`

**Authentication**: API Key via `X-API-Key` header

**Content-Type**: `multipart/form-data`

---

## Minimal cURL Example

```bash
curl -X POST \
  https://your-server.com/api/eda-files/external/upload \
  -H "X-API-Key: YOUR_API_KEY" \
  -F "file=@/path/to/file.json"
```

---

## Minimal Python Example

```python
import requests

response = requests.post(
    "https://your-server.com/api/eda-files/external/upload",
    headers={"X-API-Key": "YOUR_API_KEY"},
    files={"file": open("file.json", "rb")}
)

print(response.json())
```

---

## Required File Fields

Your CSV/JSON file must include:

- `project` or `project_name`
- `block_name`
- `experiment`
- `rtl_tag`
- `stage`

---

## Response Codes

- `201` - Success (file uploaded and processed)
- `400` - Bad Request (invalid file or missing data)
- `401` - Unauthorized (invalid/missing API key)
- `500` - Server Error (processing failed)

---

## Get Help

See `EXTERNAL_API_DOCUMENTATION.md` for complete documentation.

