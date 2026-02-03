import fs from 'fs';
import path from 'path';
// @ts-ignore - csv-parser doesn't have types
import csv from 'csv-parser';
import { pool } from '../config/database';

interface ProcessedFileData {
  project_name?: string;
  domain_name?: string;
  block_name?: string;
  experiment?: string;
  rtl_tag?: string;
  user_name?: string;
  run_directory?: string;
  run_end_time?: string;
  stage?: string;
  stage_directory?: string;
  timestamp?: string;
  // Individual timing fields (for new schema)
  internal_timing_r2r_wns?: any;
  internal_timing_r2r_tns?: any;
  internal_timing_r2r_nvp?: any;
  interface_timing_i2r_wns?: any;
  interface_timing_i2r_tns?: any;
  interface_timing_i2r_nvp?: any;
  interface_timing_r2o_wns?: any;
  interface_timing_r2o_tns?: any;
  interface_timing_r2o_nvp?: any;
  interface_timing_i2o_wns?: any;
  interface_timing_i2o_tns?: any;
  interface_timing_i2o_nvp?: any;
  hold_wns?: any;
  hold_tns?: any;
  hold_nvp?: any;
  // Individual constraint fields (for new schema)
  max_tran_wns?: any;
  max_tran_nvp?: any;
  max_cap_wns?: any;
  max_cap_nvp?: any;
  max_fanout_wns?: any;
  max_fanout_nvp?: any;
  drc_violations?: any;
  congestion_hotspot?: any;
  noise_violations?: any;
  min_pulse_width?: any;
  min_period?: any;
  double_switching?: any;
  // Combined fields (for backward compatibility)
  internal_timing?: string;
  interface_timing?: string;
  max_tran_wns_nvp?: string;
  max_cap_wns_nvp?: string;
  noise?: string;
  mpw_min_period_double_switching?: string;
  congestion_drc_metrics?: string;
  area?: string;
  inst_count?: string;
  utilization?: string;
  logs_errors_warnings?: string;
  log_errors?: any;
  log_warnings?: any;
  log_critical?: any;
  run_status?: string;
  runtime?: string;
  memory_usage?: any;
  ai_based_overall_summary?: string;
  ai_summary?: string;
  ir_static?: any;
  ir_dynamic?: any;
  em_power?: any;
  em_signal?: any;
  em_power_signal?: string;
  pv_drc_base?: any;
  pv_drc_metal?: any;
  pv_drc_antenna?: any;
  pv_drc_base_metal_antenna?: string;
  lvs?: any;
  erc?: any;
  r2g_lec?: any;
  g2g_lec?: any;
  lec?: string;
  setup_path_groups?: any;
  drv_violations?: any;
  metal_density_max?: any;
  [key: string]: any; // For any additional fields
}

class FileProcessorService {
  private outputFolder: string;

  constructor() {
    // Set output folder path - create if it doesn't exist
    // Use environment variable if set, otherwise use default location
    const customPath = process.env.EDA_OUTPUT_FOLDER;
    if (customPath) {
      this.outputFolder = path.resolve(customPath);
    } else {
      this.outputFolder = path.join(process.cwd(), 'output');
    }
    this.ensureOutputFolderExists();
  }

  private ensureOutputFolderExists(): void {
    if (!fs.existsSync(this.outputFolder)) {
      fs.mkdirSync(this.outputFolder, { recursive: true });
    }
  }

  getOutputFolder(): string {
    return this.outputFolder;
  }

  /**
   * Process CSV file and extract data
   */
  async processCSVFile(filePath: string): Promise<ProcessedFileData[]> {
    return new Promise((resolve, reject) => {
      const results: ProcessedFileData[] = [];
      
      fs.createReadStream(filePath, { encoding: 'utf8' })
        .pipe(csv({
          // Handle multi-line values properly
          headers: true,
          // Map headers to handle spaces and special characters
          mapHeaders: ({ header }: { header: string }) => header.trim(),
          // Handle quoted fields with newlines
          quote: '"',
          escape: '"'
        }))
        .on('data', (data: any) => {
          try {
            // Process row data
            results.push(this.normalizeData(data));
          } catch (error: any) {
            // Continue processing other rows even if one fails
          }
        })
        .on('end', () => {
          resolve(results);
        })
        .on('error', (error: Error) => {
          reject(error);
        });
    });
  }

  /**
   * Process JSON file and extract data
   */
  async processJSONFile(filePath: string): Promise<ProcessedFileData[]> {
    try {
      const fileContent = fs.readFileSync(filePath, 'utf-8');
      const data = JSON.parse(fileContent);
      
      // Handle PD JSON structure with nested stages
      if (data.stages && typeof data.stages === 'object' && !Array.isArray(data.stages)) {
        const stageNames = Object.keys(data.stages);
        const results: ProcessedFileData[] = [];
        
        // Process each stage
        for (const [stageName, stageData] of Object.entries(data.stages)) {
          if (typeof stageData === 'object' && stageData !== null) {
            // Create a clean merged data object (exclude the stages property to avoid recursion)
            const { stages, last_updated, ...topLevelData } = data;
            const mergedData = {
              ...topLevelData,
              ...(stageData as any),
              stage: stageName
            };
            
            // Convert PD JSON structure to normalized format
            const normalized = this.normalizePDJSONData(mergedData);
            if (normalized) {
              results.push(normalized);
            }
          }
        }
        
        if (results.length > 0) {
          return results;
        }
      }
      
      // Handle both array and single object (legacy format)
      const dataArray = Array.isArray(data) ? data : [data];
      
      return dataArray.map(item => this.normalizeData(item));
    } catch (error: any) {
      throw new Error(`Failed to parse JSON file: ${error.message}`);
    }
  }

  /**
   * Normalize PD JSON data structure to match database schema
   */
  private normalizePDJSONData(data: any): ProcessedFileData | null {
    try {
      const normalized: ProcessedFileData = {};
      
      // Helper function to clean and normalize values
      const cleanValue = (value: any): any => {
        if (value === null || value === undefined) {
          return null;
        }
        
        if (typeof value === 'string') {
          const trimmed = value.trim();
          // Convert "NA", "N/A", "n/a", etc. to null
          if (trimmed === '' || 
              trimmed.toUpperCase() === 'NA' || 
              trimmed.toUpperCase() === 'N/A' ||
              trimmed.toUpperCase() === 'NULL' ||
              trimmed === '-') {
            return null;
          }
          return trimmed;
        }
        
        return value;
      };

      // Helper to convert null to undefined (for string fields)
      const toUndefined = (value: any): string | undefined => {
        if (value === null || value === undefined) {
          return undefined;
        }
        
        // If it's a string, clean it
        if (typeof value === 'string') {
          const cleaned = cleanValue(value);
          return cleaned === null ? undefined : cleaned;
        }
        
        // For non-string values, convert to string
        return String(value);
      };
      
      // Helper to convert value to string or undefined (for numeric fields that should be stored as strings)
      const toStringOrUndefined = (value: any): string | undefined => {
        if (value === null || value === undefined) {
          return undefined;
        }
        
        // If it's a number, convert to string
        if (typeof value === 'number') {
          return value.toString();
        }
        
        // If it's a string, clean it
        if (typeof value === 'string') {
          const cleaned = cleanValue(value);
          return cleaned === null ? undefined : cleaned;
        }
        
        return String(value);
      };
      
      // Extract top-level fields
      normalized.project_name = toUndefined(data.project);
      normalized.block_name = toUndefined(data.block_name);
      normalized.experiment = toUndefined(data.experiment);
      normalized.rtl_tag = toUndefined(data.rtl_tag);
      normalized.run_directory = toUndefined(data.run_directory);
      normalized.user_name = toUndefined(data.user_name);
      normalized.stage = toUndefined(data.stage);
      
      
      // Parse timestamp
      if (data.timestamp) {
        try {
          const timestamp = new Date(data.timestamp).toISOString();
          normalized.run_end_time = timestamp || undefined;
        } catch (e) {
          // Ignore date parsing errors
        }
      }
      
      // Preserve individual timing fields for new schema (don't combine them)
      normalized.internal_timing_r2r_wns = data.internal_timing_r2r_wns;
      normalized.internal_timing_r2r_tns = data.internal_timing_r2r_tns;
      normalized.internal_timing_r2r_nvp = data.internal_timing_r2r_nvp;
      
      // Also create combined field for backward compatibility
      if (data.internal_timing_r2r_wns !== undefined || 
          data.internal_timing_r2r_tns !== undefined || 
          data.internal_timing_r2r_nvp !== undefined) {
        const parts: string[] = [];
        if (data.internal_timing_r2r_wns !== null && 
            data.internal_timing_r2r_wns !== undefined && 
            cleanValue(data.internal_timing_r2r_wns) !== null) {
          parts.push(`WNS: ${data.internal_timing_r2r_wns}`);
        }
        if (data.internal_timing_r2r_tns !== null && 
            data.internal_timing_r2r_tns !== undefined && 
            cleanValue(data.internal_timing_r2r_tns) !== null) {
          parts.push(`TNS: ${data.internal_timing_r2r_tns}`);
        }
        if (data.internal_timing_r2r_nvp !== null && 
            data.internal_timing_r2r_nvp !== undefined && 
            cleanValue(data.internal_timing_r2r_nvp) !== null) {
          parts.push(`NVP: ${data.internal_timing_r2r_nvp}`);
        }
        normalized.internal_timing = parts.length > 0 ? parts.join(', ') : undefined;
      }
      
      // Preserve individual interface timing fields for new schema
      normalized.interface_timing_i2r_wns = data.interface_timing_i2r_wns;
      normalized.interface_timing_i2r_tns = data.interface_timing_i2r_tns;
      normalized.interface_timing_i2r_nvp = data.interface_timing_i2r_nvp;
      normalized.interface_timing_r2o_wns = data.interface_timing_r2o_wns;
      normalized.interface_timing_r2o_tns = data.interface_timing_r2o_tns;
      normalized.interface_timing_r2o_nvp = data.interface_timing_r2o_nvp;
      normalized.interface_timing_i2o_wns = data.interface_timing_i2o_wns;
      normalized.interface_timing_i2o_tns = data.interface_timing_i2o_tns;
      normalized.interface_timing_i2o_nvp = data.interface_timing_i2o_nvp;
      
      // Also create combined field for backward compatibility
      const interfaceTimingParts: string[] = [];
      const interfaceFields = [
        { wns: data.interface_timing_i2r_wns, tns: data.interface_timing_i2r_tns, nvp: data.interface_timing_i2r_nvp, label: 'I2R' },
        { wns: data.interface_timing_r2o_wns, tns: data.interface_timing_r2o_tns, nvp: data.interface_timing_r2o_nvp, label: 'R2O' },
        { wns: data.interface_timing_i2o_wns, tns: data.interface_timing_i2o_tns, nvp: data.interface_timing_i2o_nvp, label: 'I2O' }
      ];
      
      for (const field of interfaceFields) {
        if (field.wns !== null && field.wns !== undefined && cleanValue(field.wns) !== null) {
          interfaceTimingParts.push(`${field.label}: WNS=${field.wns}`);
        }
        if (field.tns !== null && field.tns !== undefined && cleanValue(field.tns) !== null) {
          interfaceTimingParts.push(`TNS=${field.tns}`);
        }
        if (field.nvp !== null && field.nvp !== undefined && cleanValue(field.nvp) !== null) {
          interfaceTimingParts.push(`NVP=${field.nvp}`);
        }
      }
      normalized.interface_timing = interfaceTimingParts.length > 0 ? interfaceTimingParts.join(', ') : undefined;
      
      // Preserve individual constraint fields for new schema
      normalized.max_tran_wns = data.max_tran_wns;
      normalized.max_tran_nvp = data.max_tran_nvp;
      normalized.max_cap_wns = data.max_cap_wns;
      normalized.max_cap_nvp = data.max_cap_nvp;
      normalized.max_fanout_wns = data.max_fanout_wns;
      normalized.max_fanout_nvp = data.max_fanout_nvp;
      normalized.hold_wns = data.hold_wns;
      normalized.hold_tns = data.hold_tns;
      normalized.hold_nvp = data.hold_nvp;
      normalized.drc_violations = data.drc_violations;
      normalized.congestion_hotspot = data.congestion_hotspot;
      normalized.noise_violations = data.noise_violations;
      
      // Also create combined fields for backward compatibility
      if (data.max_tran_wns !== undefined || data.max_tran_nvp !== undefined) {
        const parts: string[] = [];
        if (data.max_tran_wns !== null && 
            data.max_tran_wns !== undefined && 
            cleanValue(data.max_tran_wns) !== null) {
          parts.push(`WNS: ${data.max_tran_wns}`);
        }
        if (data.max_tran_nvp !== null && 
            data.max_tran_nvp !== undefined && 
            cleanValue(data.max_tran_nvp) !== null) {
          parts.push(`NVP: ${data.max_tran_nvp}`);
        }
        normalized.max_tran_wns_nvp = parts.length > 0 ? parts.join(', ') : undefined;
      }
      
      if (data.max_cap_wns !== undefined || data.max_cap_nvp !== undefined) {
        const parts: string[] = [];
        if (data.max_cap_wns !== null && 
            data.max_cap_wns !== undefined && 
            cleanValue(data.max_cap_wns) !== null) {
          parts.push(`WNS: ${data.max_cap_wns}`);
        }
        if (data.max_cap_nvp !== null && 
            data.max_cap_nvp !== undefined && 
            cleanValue(data.max_cap_nvp) !== null) {
          parts.push(`NVP: ${data.max_cap_nvp}`);
        }
        normalized.max_cap_wns_nvp = parts.length > 0 ? parts.join(', ') : undefined;
      }
      
      normalized.noise = toUndefined(data.noise_violations);
      
      // Preserve individual fields for new schema
      normalized.min_pulse_width = data.min_pulse_width;
      normalized.min_period = data.min_period;
      normalized.double_switching = data.double_switching;
      normalized.stage_directory = data.stage_directory;
      normalized.memory_usage = data.memory_usage;
      
      // Also create combined fields for backward compatibility
      const mpwParts: string[] = [];
      if (data.min_pulse_width !== null && cleanValue(data.min_pulse_width) !== null) {
        mpwParts.push(`MPW: ${data.min_pulse_width}`);
      }
      if (data.min_period !== null && cleanValue(data.min_period) !== null) {
        mpwParts.push(`Min Period: ${data.min_period}`);
      }
      if (data.double_switching !== null && cleanValue(data.double_switching) !== null) {
        mpwParts.push(`Double Switching: ${data.double_switching}`);
      }
      normalized.mpw_min_period_double_switching = mpwParts.length > 0 ? mpwParts.join(', ') : undefined;
      
      const congestionParts: string[] = [];
      if (data.drc_violations !== null && cleanValue(data.drc_violations) !== null) {
        congestionParts.push(`DRC: ${data.drc_violations}`);
      }
      if (data.congestion_hotspot !== null && cleanValue(data.congestion_hotspot) !== null) {
        congestionParts.push(`Congestion: ${data.congestion_hotspot}`);
      }
      normalized.congestion_drc_metrics = congestionParts.length > 0 ? congestionParts.join(', ') : undefined;
      
      // Area, instance count, utilization (these can be numbers or strings)
      normalized.area = toStringOrUndefined(data.area);
      normalized.inst_count = toStringOrUndefined(data.inst_count);
      normalized.utilization = toStringOrUndefined(data.utilization);
      
      // Preserve individual log fields for new schema
      normalized.log_errors = data.log_errors;
      normalized.log_warnings = data.log_warnings;
      normalized.log_critical = data.log_critical;
      
      // Also create combined field for backward compatibility
      const logParts: string[] = [];
      if (data.log_errors !== null && data.log_errors !== undefined) {
        logParts.push(`Errors: ${data.log_errors}`);
      }
      if (data.log_warnings !== null && data.log_warnings !== undefined) {
        logParts.push(`Warnings: ${data.log_warnings}`);
      }
      if (data.log_critical !== null && data.log_critical !== undefined) {
        logParts.push(`Critical: ${data.log_critical}`);
      }
      normalized.logs_errors_warnings = logParts.length > 0 ? logParts.join(', ') : undefined;
      
      // Run status and runtime
      normalized.run_status = toUndefined(data.run_status);
      normalized.runtime = toUndefined(data.runtime);
      
      // AI summary
      normalized.ai_based_overall_summary = toUndefined(data.ai_summary);
      
      // IR static
      normalized.ir_static = toUndefined(data.ir_static);
      
      // Preserve individual power/IR/EM fields for new schema
      normalized.ir_static = data.ir_static;
      normalized.ir_dynamic = data.ir_dynamic;
      normalized.em_power = data.em_power;
      normalized.em_signal = data.em_signal;
      
      // Preserve individual PV DRC fields for new schema
      normalized.pv_drc_base = data.pv_drc_base;
      normalized.pv_drc_metal = data.pv_drc_metal;
      normalized.pv_drc_antenna = data.pv_drc_antenna;
      normalized.lvs = data.lvs;
      normalized.erc = data.erc;
      normalized.r2g_lec = data.r2g_lec;
      normalized.g2g_lec = data.g2g_lec;
      
      // Also preserve setup_path_groups and drv_violations for new schema
      normalized.setup_path_groups = data.setup_path_groups;
      normalized.drv_violations = data.drv_violations;
      
      // Also create combined fields for backward compatibility
      const emParts: string[] = [];
      if (data.em_power !== null && cleanValue(data.em_power) !== null) {
        emParts.push(`Power: ${data.em_power}`);
      }
      if (data.em_signal !== null && cleanValue(data.em_signal) !== null) {
        emParts.push(`Signal: ${data.em_signal}`);
      }
      normalized.em_power_signal = emParts.length > 0 ? emParts.join(', ') : undefined;
      
      const pvParts: string[] = [];
      if (data.pv_drc_base !== null && cleanValue(data.pv_drc_base) !== null) {
        pvParts.push(`Base: ${data.pv_drc_base}`);
      }
      if (data.pv_drc_metal !== null && cleanValue(data.pv_drc_metal) !== null) {
        pvParts.push(`Metal: ${data.pv_drc_metal}`);
      }
      if (data.pv_drc_antenna !== null && cleanValue(data.pv_drc_antenna) !== null) {
        pvParts.push(`Antenna: ${data.pv_drc_antenna}`);
      }
      normalized.pv_drc_base_metal_antenna = pvParts.length > 0 ? pvParts.join(', ') : undefined;
      
      const lecParts: string[] = [];
      if (data.r2g_lec !== null && cleanValue(data.r2g_lec) !== null) {
        lecParts.push(`R2G: ${data.r2g_lec}`);
      }
      if (data.g2g_lec !== null && cleanValue(data.g2g_lec) !== null) {
        lecParts.push(`G2G: ${data.g2g_lec}`);
      }
      if (data.erc !== null && cleanValue(data.erc) !== null) {
        lecParts.push(`ERC: ${data.erc}`);
      }
      normalized.lec = lecParts.length > 0 ? lecParts.join(', ') : undefined;
      
      return normalized;
    } catch (error: any) {
      return null;
    }
  }

  /**
   * Normalize data keys to match database column names
   */
  private normalizeData(data: any): ProcessedFileData {
    const normalized: ProcessedFileData = {};
    
    // Helper function to clean and normalize values
    const cleanValue = (value: any): any => {
      if (value === null || value === undefined) {
        return null;
      }
      
      if (typeof value === 'string') {
        const trimmed = value.trim();
        // Convert "NA", "N/A", "n/a", etc. to null
        if (trimmed === '' || 
            trimmed.toUpperCase() === 'NA' || 
            trimmed.toUpperCase() === 'N/A' ||
            trimmed.toUpperCase() === 'NULL' ||
            trimmed === '-') {
          return null;
        }
        return trimmed;
      }
      
      return value;
    };
    
    // Clean and trim all values
    const cleanedData: any = {};
    for (const [key, value] of Object.entries(data)) {
      const cleanKey = key.trim();
      cleanedData[cleanKey] = cleanValue(value);
    }
    
    // Map various possible column name variations to our standard names
    const columnMappings: { [key: string]: string } = {
      // Project and domain
      'project': 'project_name',
      'project_name': 'project_name',
      'projectname': 'project_name',
      'Project': 'project_name',
      'Project Name': 'project_name',
      
      'domain': 'domain_name',
      'domain_name': 'domain_name',
      'domainname': 'domain_name',
      'Domain': 'domain_name',
      'Domain Name': 'domain_name',
      'PD': 'domain_name', // Physical Design domain code
      
      // Physical Design columns
      'block_name': 'block_name',
      'block': 'block_name',
      'Block Name': 'block_name',
      
      'experiment': 'experiment',
      'Experiment': 'experiment',
      
      'RTL _tag': 'rtl_tag',
      'rtl_tag': 'rtl_tag',
      'RTL Tag': 'rtl_tag',
      'rtl tag': 'rtl_tag',
      
      'user_name': 'user_name',
      'user': 'user_name',
      'User Name': 'user_name',
      
      'run_directory': 'run_directory',
      'run directory': 'run_directory',
      'Run Directory': 'run_directory',
      
      'run end time': 'run_end_time',
      'run_end_time': 'run_end_time',
      'Run End Time': 'run_end_time',
      
      'stage': 'stage',
      'Stage': 'stage',
      
      'internal timing': 'internal_timing',
      'internal_timing': 'internal_timing',
      'Internal Timing': 'internal_timing',
      
      'Interface timing': 'interface_timing',
      'interface_timing': 'interface_timing',
      'interface timing': 'interface_timing',
      
      'Max tran (WNS/NVP)': 'max_tran_wns_nvp',
      'max_tran_wns_nvp': 'max_tran_wns_nvp',
      'max tran': 'max_tran_wns_nvp',
      
      'Max cap (WNS/NVP)': 'max_cap_wns_nvp',
      'max_cap_wns_nvp': 'max_cap_wns_nvp',
      'max cap': 'max_cap_wns_nvp',
      
      'Noise': 'noise',
      'noise': 'noise',
      
      'MPW/min period/Double switching': 'mpw_min_period_double_switching',
      'mpw_min_period_double_switching': 'mpw_min_period_double_switching',
      
      'Congestion/DRC metrics': 'congestion_drc_metrics',
      'congestion_drc_metrics': 'congestion_drc_metrics',
      'Congestion DRC metrics': 'congestion_drc_metrics',
      
      'Area': 'area',
      'area': 'area',
      
      'Inst count': 'inst_count',
      'inst_count': 'inst_count',
      'Inst Count': 'inst_count',
      
      'Utilization': 'utilization',
      'utilization': 'utilization',
      
      'Logs Errors & Warnings': 'logs_errors_warnings',
      'logs_errors_warnings': 'logs_errors_warnings',
      'Logs Errors Warnings': 'logs_errors_warnings',
      
      'run status (pass/fail/continue_with_error)': 'run_status',
      'run_status': 'run_status',
      'Run Status': 'run_status',
      'run status': 'run_status',
      
      'runtime': 'runtime',
      'Runtime': 'runtime',
      
      'AI based overall summary and suggestions': 'ai_based_overall_summary',
      'ai_based_overall_summary': 'ai_based_overall_summary',
      'AI Summary': 'ai_based_overall_summary',
      
      'IR (Static)': 'ir_static',
      'ir_static': 'ir_static',
      'IR Static': 'ir_static',
      
      'EM (power, signal)': 'em_power_signal',
      'em_power_signal': 'em_power_signal',
      'EM power signal': 'em_power_signal',
      
      'PV (DRC (Base drc, metal drc, antenna)': 'pv_drc_base_metal_antenna',
      'pv_drc_base_metal_antenna': 'pv_drc_base_metal_antenna',
      'PV DRC': 'pv_drc_base_metal_antenna',
      
      'LVS': 'lvs',
      'lvs': 'lvs',
      
      'LEC': 'lec',
      'lec': 'lec',
    };

    // Normalize all keys
    for (const [key, value] of Object.entries(cleanedData)) {
      const normalizedKey = columnMappings[key] || key;
      // Only set value if it's not null or undefined (empty strings and "NA" are already converted to null)
      if (value !== null && value !== undefined) {
        normalized[normalizedKey] = value;
      }
    }

    return normalized;
  }

  /**
   * Map normalized domain name to standard domain name
   */
  private mapToStandardDomain(normalized: string): string {
    // Handle numeric/invalid domains (like timestamps) - return empty to skip
    if (/^\d+$/.test(normalized)) {
      return ''; // Skip invalid numeric domains
    }
    
    // Map "pd" abbreviation to Physical Design
    if (normalized === 'pd' || normalized === 'physical') {
      return 'physical design';
    }
    
    // Map all variations to the 4 standard domains
    if (normalized.includes('physical') && (normalized.includes('design') || normalized.includes('domain'))) {
      return 'physical design';
    } else if (normalized.includes('design') && normalized.includes('verification')) {
      return 'design verification';
    } else if (normalized.includes('register') && normalized.includes('transfer') && normalized.includes('level')) {
      return 'register transfer level';
    } else if (normalized.includes('rtl')) {
      return 'register transfer level';
    } else if (normalized.includes('testability') || normalized.includes('dft')) {
      return 'design for testability';
    } else if (normalized.includes('analog') && normalized.includes('layout')) {
      return 'analog layout';
    }
    
    return normalized;
  }

  /**
   * Normalize domain name to handle typos and variations
   */
  private normalizeDomainName(domainName: string): string {
    // Remove extra spaces and convert to lowercase
    let normalized = domainName.trim().toLowerCase().replace(/\s+/g, ' ');
    
    // Fix common typos
    normalized = normalized
      .replace(/phyiscal/g, 'physical')      // Fix: phyiscal -> physical
      .replace(/deisgn/g, 'design')          // Fix: deisgn -> design
      .replace(/desing/g, 'design')          // Fix: desing -> design
      .replace(/desgin/g, 'design')          // Fix: desgin -> design
      .replace(/verifcation/g, 'verification')  // Fix: verifcation -> verification
      .replace(/verificaton/g, 'verification'); // Fix: verificaton -> verification
    
    // Handle "physical domain" -> "physical design" (common typo)
    if (normalized.includes('physical') && normalized.includes('domain')) {
      normalized = normalized.replace(/domain/g, 'design');
    }
    
    // Handle "design _verification" -> "design verification" (extra space/underscore)
    normalized = normalized.replace(/_/g, ' ').replace(/\s+/g, ' ');
    
    // Map to standard domain name
    normalized = this.mapToStandardDomain(normalized.trim());
    
    return normalized.trim();
  }

  /**
   * Extract project and domain from run_directory path.
   * Format: CX_PROJ or CX_RUN_NEW / {project} / {domain} / users/...
   * Example: /CX_PROJ/semicon/pd/users/... or /CX_RUN_NEW/... → { project: "semicon", domain: "pd" }
   */
  private extractProjectAndDomainFromRunDirectory(runDirectory: string | undefined): { project: string | null; domain: string | null } {
    if (!runDirectory || typeof runDirectory !== 'string') return { project: null, domain: null };
    const trimmed = runDirectory.trim().replace(/\\/g, '/');
    const parts = trimmed.split('/').filter(Boolean);
    if (parts.length < 3) return { project: null, domain: null };
    const first = parts[0].toUpperCase();
    if (first !== 'CX_RUN_NEW' && first !== 'CX_PROJ') return { project: null, domain: null };
    const projectSegment = parts[1].trim() || null;
    const domainSegment = parts[2].trim() || null;
    return { project: projectSegment, domain: domainSegment };
  }

  /**
   * Find domain ID from domain name (with typo handling)
   */
  async findDomainId(domainName: string): Promise<number | null> {
    if (!domainName) return null;
    
    try {
      const normalized = this.normalizeDomainName(domainName);
      
      // First try exact match (case-insensitive)
      let result = await pool.query(
        'SELECT id FROM public.domains WHERE (LOWER(TRIM(name)) = LOWER($1) OR LOWER(code) = LOWER($1)) AND is_active = true',
        [domainName]
      );
      
      if (result.rows.length > 0) {
        return result.rows[0].id;
      }
      
      // Then try normalized match (handles typos)
      result = await pool.query(
        'SELECT id FROM public.domains WHERE LOWER(TRIM(name)) = $1 AND is_active = true',
        [normalized]
      );
      
      return result.rows.length > 0 ? result.rows[0].id : null;
    } catch (error) {
      return null;
    }
  }

  /**
   * Find project ID from project name
   */
  async findProjectId(projectName: string): Promise<number | null> {
    if (!projectName) return null;
    
    try {
      const result = await pool.query(
        'SELECT id FROM public.projects WHERE LOWER(name) = LOWER($1)',
        [projectName]
      );
      
      return result.rows.length > 0 ? result.rows[0].id : null;
    } catch (error) {
      return null;
    }
  }

  /**
   * Save processed file data to database
   * For JSON files with multiple stages, saves each stage as a separate record
   */
  /**
   * Save data to new Physical Design schema (blocks, runs, stages, etc.)
   */
  async saveToNewSchema(
    fileName: string,
    filePath: string,
    fileType: string,
    fileSize: number,
    processedData: ProcessedFileData[],
    uploadedBy?: number,
    filenameProject?: string,
    filenameDomain?: string
  ): Promise<number> {
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN');

      if (processedData.length === 0) {
        throw new Error('No data to save');
      }

      // Project and domain only from run_directory (CX_PROJ or CX_RUN_NEW / {project} / {domain} / users/...); e.g. pd or dv from path — no fallback
      const firstRow = processedData[0];
      const runDirForLog = firstRow.run_directory ?? '(none)';
      const { project: projectFromRunDir, domain: domainFromRunDir } = this.extractProjectAndDomainFromRunDirectory(firstRow.run_directory);
      const projectName = projectFromRunDir || firstRow.project_name || null;
      const domainName = domainFromRunDir || null;
      let domainId: number | null = null;
      if (domainName) {
        domainId = await this.findDomainId(domainName);
        console.log(`[EDA incoming file] run_directory: ${runDirForLog} → extracted project: "${projectName}", domain: "${domainName}" → domain_id: ${domainId ?? 'null'}`);
        if (domainId == null) {
          // Create domain so run can have domain_id set (e.g. "pd" or "dv" from path)
          const domainCode = domainName.toUpperCase().replace(/\s+/g, '_').substring(0, 50);
          try {
            const domainInsert = await client.query(
              `INSERT INTO public.domains (name, code, description, is_active) VALUES ($1, $2, $3, true) ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name RETURNING id`,
              [domainName.trim(), domainCode, `Domain: ${domainName.trim()}`]
            );
            domainId = domainInsert.rows[0]?.id ?? null;
            if (domainId) {
              console.log(`[EDA incoming file] Created/found domain "${domainName}" (code: ${domainCode}) → domain_id: ${domainId}`);
            }
          } catch (domainErr: any) {
            console.warn(`[EDA incoming file] Could not create domain "${domainName}":`, domainErr?.message);
          }
        }
      } else {
        console.log(`[EDA incoming file] run_directory: ${runDirForLog} → extracted project: "${projectName}", domain: (none) → domain_id not set`);
      }

      if (!projectName) {
        throw new Error('Project name is required');
      }

      // 1. Find or create project (projects table only; no Zoho)
      let projectId = await this.findProjectId(projectName);
      if (!projectId && projectName) {
        const projectResult = await client.query(
          'INSERT INTO public.projects (name, created_by) VALUES ($1, $2) RETURNING id',
          [projectName, uploadedBy || null]
        );
        projectId = projectResult.rows[0].id;
      }
      if (!projectId) {
        throw new Error(`Project "${projectName}" not found and could not be created`);
      }

      // 2. Get block name from first row
      const blockName = firstRow.block_name;
      if (!blockName) {
        throw new Error('Block name is required');
      }

      // 3. Find block - only blocks that already exist in DB (no Zoho)
      const blockResult = await client.query(
        'SELECT id FROM public.blocks WHERE project_id = $1 AND block_name = $2',
        [projectId, blockName]
      );
      let blockId: number | null = null;
      if (blockResult.rows.length > 0) {
        blockId = blockResult.rows[0].id;
      } else {
        throw new Error(
          `Block "${blockName}" does not exist in the database for project "${projectName}". ` +
          `Only blocks that already exist in the DB can receive EDA data. Run setup first to add the block.`
        );
      }

      // 4. Get run info from first row
      const experiment = firstRow.experiment;
      const incomingRtlTagRaw = (firstRow.rtl_tag ?? '').toString().trim();
      const userName = firstRow.user_name;
      const runDirectory = firstRow.run_directory;
      const lastUpdated = firstRow.run_end_time ? new Date(firstRow.run_end_time) : new Date();

      if (!experiment) {
        throw new Error('Experiment is required');
      }

      // 5. Find run (experiment) - runs table only (no Zoho). Only existing runs get EDA data.
      const runResult = await client.query(
        `SELECT id, rtl_tag FROM public.runs 
         WHERE block_id = $1 AND experiment = $2`,
        [blockId, experiment]
      );
      let runId: number | null = null;
      if (runResult.rows.length > 0) {
        runId = runResult.rows[0].id;
        const existingRtlTag = runResult.rows[0].rtl_tag?.toString().trim() ?? '';
        // RTL tag belongs to user+block (user_block_rtl_tags). A user or block can have multiple RTL tags.
        // Use file's RTL tag when present; otherwise keep run's. Allow entry when uploader has this RTL tag for this block.
        const rtlTagToSet = incomingRtlTagRaw.length > 0 ? incomingRtlTagRaw : existingRtlTag;
        const rtlTagToSetLower = rtlTagToSet.toLowerCase();
        if (uploadedBy != null && rtlTagToSet.length > 0) {
          const tableExists = await client.query(
            `SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_block_rtl_tags')`
          );
          if (tableExists.rows[0]?.exists === true) {
            const allowed = await client.query(
              `SELECT 1 FROM user_block_rtl_tags WHERE user_id = $1 AND block_id = $2 AND LOWER(rtl_tag) = $3 LIMIT 1`,
              [uploadedBy, blockId, rtlTagToSetLower]
            );
            if (allowed.rows.length === 0) {
              throw new Error(
                `RTL tag "${rtlTagToSet}" for block "${blockName}" is not assigned to you. ` +
                `Create or select this RTL tag in Experiment Setup for this block first, then upload EDA files.`
              );
            }
          }
        }
        await client.query(
          'UPDATE public.runs SET rtl_tag = $1, user_name = $2, run_directory = $3, last_updated = $4, domain_id = $5 WHERE id = $6',
          [rtlTagToSet, userName, runDirectory, lastUpdated, domainId, runId]
        );
      } else {
        throw new Error(
          `Experiment "${experiment}" does not exist in the database for block "${blockName}" in project "${projectName}". ` +
          `Only blocks and experiments that already exist in the DB can receive EDA data. Run setup first.`
        );
      }

      // 6. Process each stage
      let firstStageId: number | null = null;
      for (const stageData of processedData) {
        const stageName = stageData.stage;
        if (!stageName) {
          continue;
        }

        // Parse timestamp
        const timestamp = stageData.run_end_time ? new Date(stageData.run_end_time) : null;

        // Create stage record
        const stageResult = await client.query(
          `INSERT INTO public.stages (
            run_id, stage_name, timestamp, stage_directory, run_status, runtime, memory_usage,
            log_errors, log_warnings, log_critical, area, inst_count, utilization,
            metal_density_max, min_pulse_width, min_period, double_switching
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
          ON CONFLICT (run_id, stage_name) DO UPDATE SET
            timestamp = EXCLUDED.timestamp,
            stage_directory = EXCLUDED.stage_directory,
            run_status = EXCLUDED.run_status,
            runtime = EXCLUDED.runtime,
            memory_usage = EXCLUDED.memory_usage,
            log_errors = EXCLUDED.log_errors,
            log_warnings = EXCLUDED.log_warnings,
            log_critical = EXCLUDED.log_critical,
            area = EXCLUDED.area,
            inst_count = EXCLUDED.inst_count,
            utilization = EXCLUDED.utilization,
            metal_density_max = EXCLUDED.metal_density_max,
            min_pulse_width = EXCLUDED.min_pulse_width,
            min_period = EXCLUDED.min_period,
            double_switching = EXCLUDED.double_switching
          RETURNING id`,
          [
            runId,
            stageName,
            timestamp,
            stageData.stage_directory || null,
            stageData.run_status || null,
            stageData.runtime || null,
            stageData.memory_usage || null,
            this.parseToString(stageData.log_errors) || '0',
            this.parseToString(stageData.log_warnings) || '0',
            this.parseToString(stageData.log_critical) || '0',
            this.parseToString(stageData.area),
            this.parseToString(stageData.inst_count),
            this.parseToString(stageData.utilization),
            this.parseToString(stageData.metal_density_max),
            stageData.min_pulse_width || null,
            stageData.min_period || null,
            stageData.double_switching || null,
          ]
        );

        const stageId = stageResult.rows[0].id;
        if (!firstStageId) firstStageId = stageId;

        // Save timing metrics
        await this.saveTimingMetrics(client, stageId, stageData);
        
        // Save constraint metrics
        await this.saveConstraintMetrics(client, stageId, stageData);
        
        // Save path groups
        await this.savePathGroups(client, stageId, stageData);
        
        // Save DRV violations
        await this.saveDRVViolations(client, stageId, stageData);
        
        // Save power/IR/EM checks
        await this.savePowerIREMChecks(client, stageId, stageData);
        
        // Save physical verification
        await this.savePhysicalVerification(client, stageId, stageData);
        
        // Save AI summary
        if (stageData.ai_based_overall_summary || stageData.ai_summary) {
          await this.saveAISummary(client, stageId, stageData.ai_based_overall_summary || stageData.ai_summary);
        }
      }

      await client.query('COMMIT');
      
      return firstStageId || 0;
    } catch (error: any) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  private parseNumeric(value: any): number | null {
    if (value === null || value === undefined || value === 'N/A' || value === 'NA') return null;
    if (typeof value === 'number') return value;
    if (typeof value === 'string') {
      const parsed = parseFloat(value);
      return isNaN(parsed) ? null : parsed;
    }
    return null;
  }

  private parseToString(value: any): string | null {
    if (value === null || value === undefined) return null;
    if (value === 'N/A' || value === 'NA') return 'N/A';
    // Convert to string, preserving the original format
    return String(value);
  }

  private async saveTimingMetrics(client: any, stageId: number, stageData: any): Promise<void> {
    const timingData = {
      internal_r2r_wns: this.parseToString(stageData.internal_timing_r2r_wns),
      internal_r2r_tns: this.parseToString(stageData.internal_timing_r2r_tns),
      internal_r2r_nvp: this.parseToString(stageData.internal_timing_r2r_nvp),
      interface_i2r_wns: this.parseToString(stageData.interface_timing_i2r_wns),
      interface_i2r_tns: this.parseToString(stageData.interface_timing_i2r_tns),
      interface_i2r_nvp: this.parseToString(stageData.interface_timing_i2r_nvp),
      interface_r2o_wns: this.parseToString(stageData.interface_timing_r2o_wns),
      interface_r2o_tns: this.parseToString(stageData.interface_timing_r2o_tns),
      interface_r2o_nvp: this.parseToString(stageData.interface_timing_r2o_nvp),
      interface_i2o_wns: this.parseToString(stageData.interface_timing_i2o_wns),
      interface_i2o_tns: this.parseToString(stageData.interface_timing_i2o_tns),
      interface_i2o_nvp: this.parseToString(stageData.interface_timing_i2o_nvp),
      hold_wns: this.parseToString(stageData.hold_wns),
      hold_tns: this.parseToString(stageData.hold_tns),
      hold_nvp: this.parseToString(stageData.hold_nvp),
    };

    await client.query(
      `INSERT INTO public.stage_timing_metrics (
        stage_id, internal_r2r_wns, internal_r2r_tns, internal_r2r_nvp,
        interface_i2r_wns, interface_i2r_tns, interface_i2r_nvp,
        interface_r2o_wns, interface_r2o_tns, interface_r2o_nvp,
        interface_i2o_wns, interface_i2o_tns, interface_i2o_nvp,
        hold_wns, hold_tns, hold_nvp
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
      ON CONFLICT (stage_id) DO UPDATE SET
        internal_r2r_wns = EXCLUDED.internal_r2r_wns,
        internal_r2r_tns = EXCLUDED.internal_r2r_tns,
        internal_r2r_nvp = EXCLUDED.internal_r2r_nvp,
        interface_i2r_wns = EXCLUDED.interface_i2r_wns,
        interface_i2r_tns = EXCLUDED.interface_i2r_tns,
        interface_i2r_nvp = EXCLUDED.interface_i2r_nvp,
        interface_r2o_wns = EXCLUDED.interface_r2o_wns,
        interface_r2o_tns = EXCLUDED.interface_r2o_tns,
        interface_r2o_nvp = EXCLUDED.interface_r2o_nvp,
        interface_i2o_wns = EXCLUDED.interface_i2o_wns,
        interface_i2o_tns = EXCLUDED.interface_i2o_tns,
        interface_i2o_nvp = EXCLUDED.interface_i2o_nvp,
        hold_wns = EXCLUDED.hold_wns,
        hold_tns = EXCLUDED.hold_tns,
        hold_nvp = EXCLUDED.hold_nvp`,
      [
        stageId,
        timingData.internal_r2r_wns,
        timingData.internal_r2r_tns,
        timingData.internal_r2r_nvp,
        timingData.interface_i2r_wns,
        timingData.interface_i2r_tns,
        timingData.interface_i2r_nvp,
        timingData.interface_r2o_wns,
        timingData.interface_r2o_tns,
        timingData.interface_r2o_nvp,
        timingData.interface_i2o_wns,
        timingData.interface_i2o_tns,
        timingData.interface_i2o_nvp,
        timingData.hold_wns,
        timingData.hold_tns,
        timingData.hold_nvp,
      ]
    );
  }

  private async saveConstraintMetrics(client: any, stageId: number, stageData: any): Promise<void> {
    const constraintData = {
      max_tran_wns: this.parseToString(stageData.max_tran_wns),
      max_tran_nvp: this.parseToString(stageData.max_tran_nvp),
      max_cap_wns: this.parseToString(stageData.max_cap_wns),
      max_cap_nvp: this.parseToString(stageData.max_cap_nvp),
      max_fanout_wns: this.parseToString(stageData.max_fanout_wns),
      max_fanout_nvp: this.parseToString(stageData.max_fanout_nvp),
      drc_violations: this.parseToString(stageData.drc_violations),
      congestion_hotspot: stageData.congestion_hotspot || null,
      noise_violations: stageData.noise_violations || null,
    };

    await client.query(
      `INSERT INTO public.stage_constraint_metrics (
        stage_id, max_tran_wns, max_tran_nvp, max_cap_wns, max_cap_nvp,
        max_fanout_wns, max_fanout_nvp, drc_violations, congestion_hotspot, noise_violations
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      ON CONFLICT (stage_id) DO UPDATE SET
        max_tran_wns = EXCLUDED.max_tran_wns,
        max_tran_nvp = EXCLUDED.max_tran_nvp,
        max_cap_wns = EXCLUDED.max_cap_wns,
        max_cap_nvp = EXCLUDED.max_cap_nvp,
        max_fanout_wns = EXCLUDED.max_fanout_wns,
        max_fanout_nvp = EXCLUDED.max_fanout_nvp,
        drc_violations = EXCLUDED.drc_violations,
        congestion_hotspot = EXCLUDED.congestion_hotspot,
        noise_violations = EXCLUDED.noise_violations`,
      [
        stageId,
        constraintData.max_tran_wns,
        constraintData.max_tran_nvp,
        constraintData.max_cap_wns,
        constraintData.max_cap_nvp,
        constraintData.max_fanout_wns,
        constraintData.max_fanout_nvp,
        constraintData.drc_violations,
        constraintData.congestion_hotspot,
        constraintData.noise_violations,
      ]
    );
  }

  private async savePathGroups(client: any, stageId: number, stageData: any): Promise<void> {
    const pathGroups: any[] = [];
    
    // Save setup path groups
    if (stageData.setup_path_groups && typeof stageData.setup_path_groups === 'object') {
      for (const [groupName, groupData] of Object.entries(stageData.setup_path_groups)) {
        const group = groupData as any;
        const pathGroupData = {
          group_type: 'setup',
          group_name: groupName,
          wns: this.parseToString(group.wns),
          tns: this.parseToString(group.tns),
          nvp: this.parseToString(group.nvp),
        };
        
        await client.query(
          `INSERT INTO public.path_groups (stage_id, group_type, group_name, wns, tns, nvp)
           VALUES ($1, 'setup', $2, $3, $4, $5)
           ON CONFLICT (stage_id, group_type, group_name) DO UPDATE SET
             wns = EXCLUDED.wns, tns = EXCLUDED.tns, nvp = EXCLUDED.nvp`,
          [
            stageId,
            groupName,
            pathGroupData.wns,
            pathGroupData.tns,
            pathGroupData.nvp,
          ]
        );
        
        pathGroups.push(pathGroupData);
      }
    }

    // Save hold path groups
    if (stageData.hold_path_groups && typeof stageData.hold_path_groups === 'object') {
      for (const [groupName, groupData] of Object.entries(stageData.hold_path_groups)) {
        const group = groupData as any;
        const pathGroupData = {
          group_type: 'hold',
          group_name: groupName,
          wns: this.parseToString(group.wns),
          tns: this.parseToString(group.tns),
          nvp: this.parseToString(group.nvp),
        };
        
        await client.query(
          `INSERT INTO public.path_groups (stage_id, group_type, group_name, wns, tns, nvp)
           VALUES ($1, 'hold', $2, $3, $4, $5)
           ON CONFLICT (stage_id, group_type, group_name) DO UPDATE SET
             wns = EXCLUDED.wns, tns = EXCLUDED.tns, nvp = EXCLUDED.nvp`,
          [
            stageId,
            groupName,
            pathGroupData.wns,
            pathGroupData.tns,
            pathGroupData.nvp,
          ]
        );
        
        pathGroups.push(pathGroupData);
      }
    }
  }

  private async saveDRVViolations(client: any, stageId: number, stageData: any): Promise<void> {
    const drvViolations: any[] = [];
    
    if (stageData.drv_violations && typeof stageData.drv_violations === 'object') {
      for (const [violationType, violationData] of Object.entries(stageData.drv_violations)) {
        const violation = violationData as any;
        const drvData = {
          violation_type: violationType,
          wns: this.parseToString(violation.wns),
          tns: this.parseToString(violation.tns),
          nvp: this.parseToString(violation.nvp),
        };
        
        await client.query(
          `INSERT INTO public.drv_violations (stage_id, violation_type, wns, tns, nvp)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (stage_id, violation_type) DO UPDATE SET
             wns = EXCLUDED.wns, tns = EXCLUDED.tns, nvp = EXCLUDED.nvp`,
          [
            stageId,
            violationType,
            drvData.wns,
            drvData.tns,
            drvData.nvp,
          ]
        );
        
        drvViolations.push(drvData);
      }
    }
  }

  private async savePowerIREMChecks(client: any, stageId: number, stageData: any): Promise<void> {
    const powerData = {
      ir_static: stageData.ir_static || null,
      ir_dynamic: stageData.ir_dynamic || null,
      em_power: stageData.em_power || null,
      em_signal: stageData.em_signal || null,
    };

    await client.query(
      `INSERT INTO public.power_ir_em_checks (stage_id, ir_static, ir_dynamic, em_power, em_signal)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (stage_id) DO UPDATE SET
         ir_static = EXCLUDED.ir_static,
         ir_dynamic = EXCLUDED.ir_dynamic,
         em_power = EXCLUDED.em_power,
         em_signal = EXCLUDED.em_signal`,
      [
        stageId,
        powerData.ir_static,
        powerData.ir_dynamic,
        powerData.em_power,
        powerData.em_signal,
      ]
    );
  }

  private async savePhysicalVerification(client: any, stageId: number, stageData: any): Promise<void> {
    const pvData = {
      pv_drc_base: stageData.pv_drc_base || null,
      pv_drc_metal: stageData.pv_drc_metal || null,
      pv_drc_antenna: stageData.pv_drc_antenna || null,
      lvs: stageData.lvs || null,
      erc: stageData.erc || null,
      r2g_lec: stageData.r2g_lec || null,
      g2g_lec: stageData.g2g_lec || null,
    };

    await client.query(
      `INSERT INTO public.physical_verification (
        stage_id, pv_drc_base, pv_drc_metal, pv_drc_antenna, lvs, erc, r2g_lec, g2g_lec
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      ON CONFLICT (stage_id) DO UPDATE SET
        pv_drc_base = EXCLUDED.pv_drc_base,
        pv_drc_metal = EXCLUDED.pv_drc_metal,
        pv_drc_antenna = EXCLUDED.pv_drc_antenna,
        lvs = EXCLUDED.lvs,
        erc = EXCLUDED.erc,
        r2g_lec = EXCLUDED.r2g_lec,
        g2g_lec = EXCLUDED.g2g_lec`,
      [
        stageId,
        pvData.pv_drc_base,
        pvData.pv_drc_metal,
        pvData.pv_drc_antenna,
        pvData.lvs,
        pvData.erc,
        pvData.r2g_lec,
        pvData.g2g_lec,
      ]
    );
  }

  private async saveAISummary(client: any, stageId: number, summaryText: string | null | undefined): Promise<void> {
    if (!summaryText || summaryText.trim() === '') return;
    
    // Delete existing summary for this stage and insert new one
    await client.query('DELETE FROM public.ai_summaries WHERE stage_id = $1', [stageId]);
    await client.query(
      `INSERT INTO public.ai_summaries (stage_id, summary_text)
       VALUES ($1, $2)`,
      [stageId, summaryText]
    );

  }

  async saveFileToDatabase(
    fileName: string,
    filePath: string,
    fileType: string,
    fileSize: number,
    processedData: ProcessedFileData[],
    uploadedBy?: number,
    filenameProject?: string,
    filenameDomain?: string
  ): Promise<number> {
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN');

      // Get the first row's project and domain info (assuming all rows have same project/domain)
      const firstRow = processedData[0] || {};
      
      // Project name comes from file data only, domain from filename (or file data as fallback)
      const projectName = firstRow.project_name || null; // Project from file data only
      const domainName = filenameDomain || firstRow.domain_name || null; // Domain from filename takes priority

      // Find domain and project IDs (same for all stages)
      const domainId = domainName ? await this.findDomainId(domainName) : null;
      const projectId = projectName ? await this.findProjectId(projectName) : null;

      // Save each stage as a separate record
      const savedIds: number[] = [];
      
      for (let i = 0; i < processedData.length; i++) {
        const row = processedData[i];
        
        const insertResult = await client.query(
          `
            INSERT INTO public.eda_output_files (
              file_name, file_path, file_type, file_size,
              project_name, domain_name, domain_id, project_id,
              block_name, experiment, rtl_tag, user_name, run_directory,
              run_end_time, stage, internal_timing, interface_timing,
              max_tran_wns_nvp, max_cap_wns_nvp, noise,
              mpw_min_period_double_switching, congestion_drc_metrics,
              area, inst_count, utilization, logs_errors_warnings,
              run_status, runtime, ai_based_overall_summary,
              ir_static, em_power_signal, pv_drc_base_metal_antenna,
              lvs, lec, raw_data, processing_status, uploaded_by
            ) VALUES (
              $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13,
              $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24,
              $25, $26, $27, $28, $29, $30, $31, $32, $33, $34, $35, $36, $37
            ) RETURNING id
          `,
          [
            fileName, filePath, fileType, fileSize,
            projectName || null, domainName || null, domainId, projectId,
            row.block_name || null,
            row.experiment || null,
            row.rtl_tag || null,
            row.user_name || null,
            row.run_directory || null,
            row.run_end_time ? new Date(row.run_end_time) : null,
            row.stage || null,
            row.internal_timing || null,
            row.interface_timing || null,
            row.max_tran_wns_nvp || null,
            row.max_cap_wns_nvp || null,
            row.noise || null,
            row.mpw_min_period_double_switching || null,
            row.congestion_drc_metrics || null,
            row.area || null,
            row.inst_count || null,
            row.utilization || null,
            row.logs_errors_warnings || null,
            row.run_status || null,
            row.runtime || null,
            row.ai_based_overall_summary || null,
            row.ir_static || null,
            row.em_power_signal || null,
            row.pv_drc_base_metal_antenna || null,
            row.lvs || null,
            row.lec || null,
            JSON.stringify(processedData), // Store all rows as raw_data for reference
            'completed',
            uploadedBy || null
          ]
        );
        
        savedIds.push(insertResult.rows[0].id);
      }

      await client.query('COMMIT');
      // Return the first ID for backward compatibility
      return savedIds[0];
    } catch (error: any) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Extract domain name from filename
   * Format: projectname.domainname.json or projectname_domainname.json
   * Returns only the domain name (everything after the first dot or underscore)
   */
  private extractDomainFromFilename(fileName: string): string | null {
    // Remove file extension
    const nameWithoutExt = path.basename(fileName, path.extname(fileName));
    
    // Try splitting by dot first (e.g., "proj.physical domain.json")
    let parts: string[] = [];
    let separator: string = '';
    
    if (nameWithoutExt.includes('.')) {
      // Split by dot
      parts = nameWithoutExt.split('.');
      separator = '.';
    } else if (nameWithoutExt.includes('_')) {
      // Split by underscore
      parts = nameWithoutExt.split('_');
      separator = '_';
    } else {
      return null;
    }
    
    if (parts.length >= 2) {
      // Everything after the first separator is the domain name
      const domainName = parts.slice(1).join(separator).trim();
      
      if (domainName) {
        return domainName;
      }
    }
    return null;
  }

  /**
   * Process a file (CSV or JSON) and save to database
   */
  async processFile(filePath: string, uploadedBy?: number): Promise<number> {
    const fileName = path.basename(filePath);
    const fileExt = path.extname(filePath).toLowerCase().slice(1);
    const stats = fs.statSync(filePath);
    const fileSize = stats.size;

    let processedData: ProcessedFileData[];

    try {
      // No need to create temp record - new schema handles everything in one transaction

      // Process based on file type
      if (fileExt === 'csv') {
        processedData = await this.processCSVFile(filePath);
      } else if (fileExt === 'json') {
        processedData = await this.processJSONFile(filePath);
      } else {
        throw new Error(`Unsupported file type: ${fileExt}`);
      }

      if (processedData.length === 0) {
        throw new Error('No data found in file');
      }

      // Domain is taken only from run_directory (e.g. pd or dv in path) in saveToNewSchema — no filename or file-data override
      const fileId = await this.saveToNewSchema(
        fileName,
        filePath,
        fileExt,
        fileSize,
        processedData,
        uploadedBy,
        undefined,
        undefined
      );

      return fileId;
    } catch (error: any) {
      console.error(`Error processing file ${fileName}:`, error.message);
      throw error;
    }
  }
}

export default new FileProcessorService();

