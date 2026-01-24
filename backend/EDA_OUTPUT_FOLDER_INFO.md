# EDA Output Folder Information

## 📁 Folder Location

The EDA output folder has been created at:
```
C:\Users\2020r\ASI dashboard\backend\output
```

**Relative Path**: `backend/output/`

## 🔍 What This Folder Does

This folder is **automatically watched** by the backend API. When files are placed in this folder:

1. **File Watcher** detects new files (CSV or JSON)
2. **File Processor** extracts project name and domain name
3. **Database** stores all Physical Design data
4. **Status** is tracked (pending, processing, completed, failed)

## 📤 How to Add Files

### Method 1: Direct File Drop
Simply copy CSV or JSON files directly into:
```
C:\Users\2020r\ASI dashboard\backend\output
```
The file watcher will automatically process them.

### Method 2: API Upload (for VNC Server)
Use the API endpoint to upload files:
```
POST http://localhost:3000/api/eda-files/folder/upload
Content-Type: multipart/form-data
Body: file (your CSV or JSON file)
```

### Method 3: Authenticated Upload (from UI)
Use the "Upload File" button in the View screen of the dashboard.

## 🔧 Configuration

### Default Location
By default, the folder is created at: `backend/output/`

### Custom Location
To use a different folder, add to `backend/.env`:
```
EDA_OUTPUT_FOLDER=C:\path\to\your\custom\folder
```

## 📋 File Requirements

- **File Types**: Only CSV and JSON files are processed
- **File Size**: Maximum 100MB per file
- **Naming**: Any filename is acceptable (original name is preserved)

## 🔄 Processing Flow

1. File is detected in the folder
2. File is checked if already processed (by file path)
3. File is parsed (CSV or JSON)
4. Project name and domain name are extracted
5. Data is normalized and saved to database
6. Processing status is updated

## 📊 Monitoring

You can check:
- **Processing Status**: View in the "View" screen of the dashboard
- **API Endpoint**: `GET /api/eda-files` - List all processed files
- **Stats**: `GET /api/eda-files/stats/summary` - Get statistics

## 🚨 Important Notes

- Files are **not deleted** after processing (they remain in the folder)
- The file watcher runs **automatically** when the backend server starts
- Processing happens **asynchronously** (doesn't block the API)
- Failed files will have error messages stored in the database

## 📝 Example Usage

1. **From VNC Server**: 
   - Copy your EDA output CSV/JSON file to: `C:\Users\2020r\ASI dashboard\backend\output`
   - The file will be automatically processed

2. **Via API**:
   ```bash
   curl -X POST http://localhost:3000/api/eda-files/folder/upload \
     -F "file=@your_file.csv"
   ```

3. **Check Status**:
   - Open the dashboard
   - Go to "View" menu
   - See all processed files with their status

## 🛠️ Troubleshooting

If files are not being processed:
1. Check that the backend server is running
2. Verify the file is CSV or JSON format
3. Check the file size (must be < 100MB)
4. Check backend logs for processing errors
5. Verify database connection is working
























