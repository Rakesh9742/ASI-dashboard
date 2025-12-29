#!/bin/bash
# Example script for uploading EDA output files to ASI Dashboard
# Usage: ./example-upload.sh <api_key> <file_path> [server_url]

if [ $# -lt 2 ]; then
    echo "Usage: $0 <api_key> <file_path> [server_url]"
    echo ""
    echo "Example:"
    echo "  $0 my-api-key-123 file.json"
    echo "  $0 my-api-key-123 file.json https://api.example.com"
    exit 1
fi

API_KEY="$1"
FILE_PATH="$2"
SERVER_URL="${3:-http://localhost:3000}"

# Validate file exists
if [ ! -f "$FILE_PATH" ]; then
    echo "❌ Error: File not found: $FILE_PATH"
    exit 1
fi

# Validate file type
FILE_EXT="${FILE_PATH##*.}"
if [ "$FILE_EXT" != "csv" ] && [ "$FILE_EXT" != "json" ]; then
    echo "❌ Error: Invalid file type. Only .csv and .json files are allowed."
    exit 1
fi

echo "📤 Uploading file: $FILE_PATH"
echo "   Server: $SERVER_URL"
echo "   File size: $(stat -f%z "$FILE_PATH" 2>/dev/null || stat -c%s "$FILE_PATH" 2>/dev/null) bytes"

# Upload file
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "$SERVER_URL/api/eda-files/external/upload" \
  -H "X-API-Key: $API_KEY" \
  -F "file=@$FILE_PATH")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -eq 201 ]; then
    echo "✅ Success!"
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    exit 0
else
    echo "❌ Error: HTTP $HTTP_CODE"
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    exit 1
fi

