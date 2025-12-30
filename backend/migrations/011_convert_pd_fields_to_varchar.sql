-- ============================================================================
-- CONVERT PHYSICAL DESIGN SCHEMA FIELDS TO VARCHAR
-- ============================================================================
-- This migration converts all numeric fields (INT, FLOAT) in the Physical Design
-- schema tables to VARCHAR to handle any value including decimals, "N/A", etc.
-- ============================================================================

-- ============================================================================
-- 1. STAGE TIMING METRICS - Convert all numeric fields to VARCHAR
-- ============================================================================
ALTER TABLE stage_timing_metrics 
  ALTER COLUMN internal_r2r_wns TYPE VARCHAR(50) USING internal_r2r_wns::text,
  ALTER COLUMN internal_r2r_tns TYPE VARCHAR(50) USING internal_r2r_tns::text,
  ALTER COLUMN internal_r2r_nvp TYPE VARCHAR(50) USING internal_r2r_nvp::text,
  ALTER COLUMN interface_i2r_wns TYPE VARCHAR(50) USING interface_i2r_wns::text,
  ALTER COLUMN interface_i2r_tns TYPE VARCHAR(50) USING interface_i2r_tns::text,
  ALTER COLUMN interface_i2r_nvp TYPE VARCHAR(50) USING interface_i2r_nvp::text,
  ALTER COLUMN interface_r2o_wns TYPE VARCHAR(50) USING interface_r2o_wns::text,
  ALTER COLUMN interface_r2o_tns TYPE VARCHAR(50) USING interface_r2o_tns::text,
  ALTER COLUMN interface_r2o_nvp TYPE VARCHAR(50) USING interface_r2o_nvp::text,
  ALTER COLUMN interface_i2o_wns TYPE VARCHAR(50) USING interface_i2o_wns::text,
  ALTER COLUMN interface_i2o_tns TYPE VARCHAR(50) USING interface_i2o_tns::text,
  ALTER COLUMN interface_i2o_nvp TYPE VARCHAR(50) USING interface_i2o_nvp::text,
  ALTER COLUMN hold_wns TYPE VARCHAR(50) USING hold_wns::text,
  ALTER COLUMN hold_tns TYPE VARCHAR(50) USING hold_tns::text,
  ALTER COLUMN hold_nvp TYPE VARCHAR(50) USING hold_nvp::text;

-- ============================================================================
-- 2. STAGE CONSTRAINT METRICS - Convert all numeric fields to VARCHAR
-- ============================================================================
ALTER TABLE stage_constraint_metrics 
  ALTER COLUMN max_tran_wns TYPE VARCHAR(50) USING max_tran_wns::text,
  ALTER COLUMN max_tran_nvp TYPE VARCHAR(50) USING max_tran_nvp::text,
  ALTER COLUMN max_cap_wns TYPE VARCHAR(50) USING max_cap_wns::text,
  ALTER COLUMN max_cap_nvp TYPE VARCHAR(50) USING max_cap_nvp::text,
  ALTER COLUMN max_fanout_wns TYPE VARCHAR(50) USING max_fanout_wns::text,
  ALTER COLUMN max_fanout_nvp TYPE VARCHAR(50) USING max_fanout_nvp::text,
  ALTER COLUMN drc_violations TYPE VARCHAR(50) USING drc_violations::text;

-- ============================================================================
-- 3. STAGES TABLE - Convert numeric fields to VARCHAR
-- ============================================================================
ALTER TABLE stages 
  ALTER COLUMN log_errors TYPE VARCHAR(50) USING log_errors::text,
  ALTER COLUMN log_warnings TYPE VARCHAR(50) USING log_warnings::text,
  ALTER COLUMN log_critical TYPE VARCHAR(50) USING log_critical::text,
  ALTER COLUMN area TYPE VARCHAR(50) USING area::text,
  ALTER COLUMN inst_count TYPE VARCHAR(50) USING inst_count::text,
  ALTER COLUMN utilization TYPE VARCHAR(50) USING utilization::text,
  ALTER COLUMN metal_density_max TYPE VARCHAR(50) USING metal_density_max::text;

-- ============================================================================
-- 4. PATH GROUPS - Convert numeric fields to VARCHAR
-- ============================================================================
ALTER TABLE path_groups 
  ALTER COLUMN wns TYPE VARCHAR(50) USING wns::text,
  ALTER COLUMN tns TYPE VARCHAR(50) USING tns::text,
  ALTER COLUMN nvp TYPE VARCHAR(50) USING nvp::text;

-- ============================================================================
-- 5. DRV VIOLATIONS - Convert numeric fields to VARCHAR
-- ============================================================================
ALTER TABLE drv_violations 
  ALTER COLUMN wns TYPE VARCHAR(50) USING wns::text,
  ALTER COLUMN tns TYPE VARCHAR(50) USING tns::text,
  ALTER COLUMN nvp TYPE VARCHAR(50) USING nvp::text;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- All numeric fields in Physical Design schema have been converted to VARCHAR(50)
-- This allows storing any value including decimals, "N/A", and other text values
-- ============================================================================

