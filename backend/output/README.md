# EDA Output Files Folder

This folder is used to store files received from EDA tools via the VNC server.

## Location
- **Default Path**: `backend/output/`
- **Full Path**: `C:\Users\2020r\ASI dashboard\backend\output\`

## How It Works

1. **File Watcher**: The backend automatically watches this folder for new files
2. **File Types**: Only CSV and JSON files are processed
3. **Automatic Processing**: When a file is dropped into this folder, it will be:
   - Automatically detected by the file watcher
   - Processed to extract project name and domain name
   - Saved to the database with all Physical Design data

## API Endpoints

### Upload File via API (for VNC server)
```
POST /api/eda-files/folder/upload
Content-Type: multipart/form-data
Body: file (CSV or JSON file)
```

### List Files in Folder
```
GET /api/eda-files/folder/list
```

### Upload File (Authenticated)
```
POST /api/eda-files/upload
Authorization: Bearer <token>
Content-Type: multipart/form-data
Body: file (CSV or JSON file)
```

## Configuration

You can set a custom folder path using the environment variable:
```
EDA_OUTPUT_FOLDER=/path/to/custom/folder
```

Add this to `backend/.env` if you want to use a different location.

## File Processing

Files are processed automatically when:
- A file is uploaded via the API
- A file is dropped directly into this folder
- The file watcher detects a new file

The system extracts:
- Project name
- Domain name
- All Physical Design columns (block_name, experiment, RTL_tag, etc.)

## Notes

- Files are processed asynchronously
- Processing status is tracked in the database
- Failed files will have error messages stored
- The original file remains in this folder after processing










