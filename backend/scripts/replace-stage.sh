#!/bin/bash

# Replace Stage API - Interactive Script
# This script helps you replace a stage by uploading a file

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values (can be overridden)
BASE_URL="${BASE_URL:-http://localhost:3000}"
API_KEY="${API_KEY:-sitedafilesdata}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Replace Stage API - Interactive Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to prompt for input with default value
prompt_with_default() {
    local prompt_text=$1
    local default_value=$2
    local var_name=$3
    
    if [ -n "$default_value" ]; then
        read -p "$prompt_text [$default_value]: " input
        eval "$var_name=\${input:-$default_value}"
    else
        read -p "$prompt_text: " input
        eval "$var_name=\$input"
    fi
}

# Function to validate required input
validate_required() {
    local value=$1
    local field_name=$2
    
    if [ -z "$value" ]; then
        echo -e "${RED}Error: $field_name is required!${NC}"
        exit 1
    fi
}

# Function to validate file exists
validate_file() {
    local file_path=$1
    
    if [ ! -f "$file_path" ]; then
        echo -e "${RED}Error: File not found: $file_path${NC}"
        exit 1
    fi
    
    # Check file extension
    local ext="${file_path##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    
    if [ "$ext" != "csv" ] && [ "$ext" != "json" ]; then
        echo -e "${RED}Error: File must be CSV or JSON format. Got: .$ext${NC}"
        exit 1
    fi
}

# Get inputs from user
echo -e "${YELLOW}Enter the following information:${NC}"
echo ""

# Base URL
prompt_with_default "Base URL" "$BASE_URL" "BASE_URL"

# API Key
prompt_with_default "API Key" "$API_KEY" "API_KEY"
validate_required "$API_KEY" "API Key"

# Project name
prompt_with_default "Project Name" "project1" "PROJECT_NAME"
validate_required "$PROJECT_NAME" "Project Name"

# Block name
prompt_with_default "Block Name" "cpu_core" "BLOCK_NAME"
validate_required "$BLOCK_NAME" "Block Name"

# Experiment
prompt_with_default "Experiment" "exp_001" "EXPERIMENT"
validate_required "$EXPERIMENT" "Experiment"

# RTL Tag
prompt_with_default "RTL Tag" "v1.2.3" "RTL_TAG"
validate_required "$RTL_TAG" "RTL Tag"

# Stage name
prompt_with_default "Stage Name (e.g., syn, place, route)" "syn" "STAGE_NAME"
validate_required "$STAGE_NAME" "Stage Name"

# File path
echo ""
read -p "File Path (CSV or JSON): " FILE_PATH
validate_required "$FILE_PATH" "File Path"
validate_file "$FILE_PATH"

# Confirm before sending
echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Confirmation${NC}"
echo -e "${YELLOW}========================================${NC}"
echo -e "Base URL:    ${GREEN}$BASE_URL${NC}"
echo -e "API Key:     ${GREEN}${API_KEY:0:10}...${NC}"
echo -e "Project:     ${GREEN}$PROJECT_NAME${NC}"
echo -e "Block:       ${GREEN}$BLOCK_NAME${NC}"
echo -e "Experiment:  ${GREEN}$EXPERIMENT${NC}"
echo -e "RTL Tag:     ${GREEN}$RTL_TAG${NC}"
echo -e "Stage:       ${GREEN}$STAGE_NAME${NC}"
echo -e "File:        ${GREEN}$FILE_PATH${NC}"
echo ""

read -p "Proceed with replacing the stage? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 0
fi

# Make API call
echo ""
echo -e "${BLUE}Sending request to API...${NC}"
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "$BASE_URL/api/eda-files/external/replace-stage" \
  -H "X-API-Key: $API_KEY" \
  -F "file=@$FILE_PATH" \
  -F "project=$PROJECT_NAME" \
  -F "block_name=$BLOCK_NAME" \
  -F "experiment=$EXPERIMENT" \
  -F "rtl_tag=$RTL_TAG" \
  -F "stage_name=$STAGE_NAME")

# Extract HTTP status code (last line)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
# Extract response body (all but last line)
BODY=$(echo "$RESPONSE" | sed '$d')

# Display results
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Response${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [ "$HTTP_CODE" -eq 200 ]; then
    echo -e "${GREEN}✓ Success! (HTTP $HTTP_CODE)${NC}"
    echo ""
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    
    # Extract and display key information
    OLD_ID=$(echo "$BODY" | grep -o '"old_stage_id":[0-9]*' | grep -o '[0-9]*')
    NEW_ID=$(echo "$BODY" | grep -o '"new_stage_id":[0-9]*' | grep -o '[0-9]*')
    
    if [ -n "$OLD_ID" ] && [ -n "$NEW_ID" ]; then
        echo ""
        echo -e "${GREEN}Stage replaced successfully!${NC}"
        echo -e "  Old Stage ID: $OLD_ID"
        echo -e "  New Stage ID: $NEW_ID"
    fi
elif [ "$HTTP_CODE" -eq 400 ]; then
    echo -e "${RED}✗ Bad Request (HTTP $HTTP_CODE)${NC}"
    echo ""
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
elif [ "$HTTP_CODE" -eq 401 ]; then
    echo -e "${RED}✗ Unauthorized (HTTP $HTTP_CODE)${NC}"
    echo -e "${RED}Invalid API key!${NC}"
    echo ""
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
elif [ "$HTTP_CODE" -eq 404 ]; then
    echo -e "${RED}✗ Not Found (HTTP $HTTP_CODE)${NC}"
    echo -e "${RED}Stage, project, block, or run not found!${NC}"
    echo ""
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
elif [ "$HTTP_CODE" -eq 500 ]; then
    echo -e "${RED}✗ Server Error (HTTP $HTTP_CODE)${NC}"
    echo ""
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
else
    echo -e "${YELLOW}? Unexpected response (HTTP $HTTP_CODE)${NC}"
    echo ""
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
fi

echo ""

# Exit with appropriate code
if [ "$HTTP_CODE" -eq 200 ]; then
    exit 0
else
    exit 1
fi

