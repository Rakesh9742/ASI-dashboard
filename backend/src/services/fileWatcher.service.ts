import path from 'path';
import fileProcessorService from './fileProcessor.service';

class FileWatcherService {
  private watcher: any = null; // chokidar.FSWatcher
  private isWatching: boolean = false;
  private processingFiles: Set<string> = new Set();
  private chokidar: any = null;

  /**
   * Dynamically import chokidar
   */
  private async getChokidar() {
    if (!this.chokidar) {
      this.chokidar = (await import('chokidar')).default;
    }
    return this.chokidar;
  }

  /**
   * Start watching the output folder for new files
   */
  async startWatching(): Promise<void> {
    if (this.isWatching) {
      console.log('📁 File watcher is already running');
      return;
    }

    const chokidar = await this.getChokidar();
    const outputFolder = fileProcessorService.getOutputFolder();
    
    console.log(`📁 Starting file watcher for folder: ${outputFolder}`);
    console.log(`📁 Watching for CSV and JSON files...`);

    this.watcher = chokidar.watch(outputFolder, {
      ignored: /(^|[\/\\])\../, // Ignore dotfiles
      persistent: true,
      ignoreInitial: false, // Process existing files on startup
      awaitWriteFinish: {
        stabilityThreshold: 2000, // Wait 2 seconds after file stops changing
        pollInterval: 100
      }
    });

    this.watcher
      .on('add', async (filePath: string) => {
        await this.handleNewFile(filePath);
      })
      .on('change', async (filePath: string) => {
        // Only process if file is not already being processed
        if (!this.processingFiles.has(filePath)) {
          await this.handleNewFile(filePath);
        }
      })
      .on('error', (error: Error) => {
        console.error('File watcher error:', error);
      })
      .on('ready', () => {
        console.log(`✅ File watcher is ready and monitoring: ${outputFolder}`);
        this.isWatching = true;
      });

    // Process any existing files in the folder
    this.processExistingFiles(outputFolder);
  }

  /**
   * Stop watching the output folder
   */
  stopWatching(): void {
    if (this.watcher) {
      this.watcher.close();
      this.watcher = null;
      this.isWatching = false;
      console.log('File watcher stopped');
    }
  }

  /**
   * Handle a new file that was added to the folder
   */
  private async handleNewFile(filePath: string): Promise<void> {
    // Skip if already processing
    if (this.processingFiles.has(filePath)) {
      return;
    }

    const fileName = path.basename(filePath);
    const fileExt = path.extname(filePath).toLowerCase().slice(1);

    // Only process CSV and JSON files
    if (fileExt !== 'csv' && fileExt !== 'json') {
      console.log(`⏭️  [FILE WATCHER] Skipping file ${fileName} - unsupported type: ${fileExt}`);
      return;
    }
    
    console.log(`🔍 [FILE WATCHER] Detected new file: ${fileName} (${fileExt.toUpperCase()})`);

    // Check if file already processed by checking runs table
    // We can check by run_directory or by processing the file and checking for existing run
    // For now, we'll process and let the database handle duplicates via UNIQUE constraints

    // Mark as processing
    this.processingFiles.add(filePath);

    try {
      console.log(`\n📄 [FILE WATCHER] Processing new file: ${fileName}`);
      console.log(`📄 [FILE WATCHER] File path: ${filePath}`);
      const fileId = await fileProcessorService.processFile(filePath);
      console.log(`✅ [FILE WATCHER] Successfully processed file: ${fileName} (ID: ${fileId})`);
      console.log(`✅ [FILE WATCHER] File data saved to new Physical Design schema\n`);
    } catch (error: any) {
      console.error(`❌ [FILE WATCHER] Error processing file ${fileName}:`, error.message);
      console.error(`❌ [FILE WATCHER] Error details:`, error);
    } finally {
      // Remove from processing set after a delay to prevent immediate re-processing
      setTimeout(() => {
        this.processingFiles.delete(filePath);
      }, 5000);
    }
  }

  /**
   * Process existing files in the output folder
   */
  private async processExistingFiles(folderPath: string): Promise<void> {
    const fs = await import('fs');
    
    try {
      const files = fs.readdirSync(folderPath);
      
      for (const file of files) {
        const filePath = path.join(folderPath, file);
        const stats = fs.statSync(filePath);
        
        // Only process files (not directories)
        if (stats.isFile()) {
          const fileExt = path.extname(file).toLowerCase().slice(1);
          
          if (fileExt === 'csv' || fileExt === 'json') {
            // TODO: Update to use new Physical Design schema
            // Temporarily disabled database check - old eda_output_files table was deleted
            try {
              const { pool } = await import('../config/database');
              const result = await pool.query(
                'SELECT id FROM eda_output_files WHERE file_path = $1',
                [filePath]
              );

              if (result.rows.length === 0) {
                console.log(`📄 [FILE WATCHER] Found unprocessed file: ${file}`);
                // Process after a short delay to avoid race conditions
                setTimeout(() => {
                  this.handleNewFile(filePath);
                }, 1000);
              } else {
                console.log(`⏭️  [FILE WATCHER] File ${file} already processed (ID: ${result.rows[0].id})`);
              }
            } catch (error: any) {
              // Error checking - just process the file anyway
              console.log(`⚠️  [FILE WATCHER] Error checking file ${file}, will process anyway: ${error.message}`);
              // Process the file
              setTimeout(() => {
                this.handleNewFile(filePath);
              }, 1000);
            }
          }
        }
      }
    } catch (error: any) {
      console.error('Error processing existing files:', error.message);
    }
  }

  /**
   * Check if watcher is active
   */
  isActive(): boolean {
    return this.isWatching;
  }
}

export default new FileWatcherService();

