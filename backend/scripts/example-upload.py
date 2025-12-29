#!/usr/bin/env python3
"""
Example script for uploading EDA output files to ASI Dashboard
Usage: python example-upload.py <api_key> <file_path> [server_url]
"""

import sys
import requests
import os
from pathlib import Path

def upload_eda_file(api_key, file_path, server_url="http://localhost:3000"):
    """
    Upload an EDA output file to the ASI Dashboard server
    
    Args:
        api_key: Your API key
        file_path: Path to the file to upload
        server_url: Server URL (default: http://localhost:3000)
    
    Returns:
        True if successful, False otherwise
    """
    url = f"{server_url}/api/eda-files/external/upload"
    headers = {"X-API-Key": api_key}
    
    # Validate file exists
    if not os.path.exists(file_path):
        print(f"❌ Error: File not found: {file_path}")
        return False
    
    # Validate file type
    file_ext = Path(file_path).suffix.lower()
    if file_ext not in ['.csv', '.json']:
        print(f"❌ Error: Invalid file type. Only .csv and .json files are allowed.")
        return False
    
    print(f"📤 Uploading file: {file_path}")
    print(f"   Server: {server_url}")
    print(f"   File size: {os.path.getsize(file_path)} bytes")
    
    try:
        with open(file_path, 'rb') as f:
            files = {'file': (os.path.basename(file_path), f)}
            response = requests.post(url, headers=headers, files=files, timeout=300)
            
            if response.status_code == 201:
                data = response.json()
                print(f"✅ Success!")
                print(f"   File ID: {data['data']['fileId']}")
                print(f"   File Name: {data['data']['fileName']}")
                print(f"   Processed At: {data['data']['processedAt']}")
                return True
            else:
                error_data = response.json()
                print(f"❌ Error {response.status_code}: {error_data.get('error', 'Unknown error')}")
                print(f"   Message: {error_data.get('message', 'No message provided')}")
                return False
                
    except FileNotFoundError:
        print(f"❌ Error: File not found: {file_path}")
        return False
    except requests.exceptions.Timeout:
        print(f"❌ Error: Request timed out. The file may be too large or the server is slow.")
        return False
    except requests.exceptions.ConnectionError:
        print(f"❌ Error: Could not connect to server: {server_url}")
        print(f"   Please check if the server is running and the URL is correct.")
        return False
    except requests.exceptions.RequestException as e:
        print(f"❌ Error: Request failed: {e}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

def main():
    if len(sys.argv) < 3:
        print("Usage: python example-upload.py <api_key> <file_path> [server_url]")
        print("\nExample:")
        print("  python example-upload.py my-api-key-123 file.json")
        print("  python example-upload.py my-api-key-123 file.json https://api.example.com")
        sys.exit(1)
    
    api_key = sys.argv[1]
    file_path = sys.argv[2]
    server_url = sys.argv[3] if len(sys.argv) > 3 else "http://localhost:3000"
    
    success = upload_eda_file(api_key, file_path, server_url)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()

