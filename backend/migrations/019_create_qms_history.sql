-- ============================================================================
-- CREATE QMS HISTORY TABLE (SNAPSHOTS ON REJECTION)
-- ============================================================================
-- This migration creates the qms_checklist_versions table to store 
-- full snapshots of checklists when they are rejected.
-- ============================================================================
CREATE TABLE IF NOT EXISTS qms_checklist_versions (
    id SERIAL PRIMARY KEY,
    checklist_id INTEGER NOT NULL REFERENCES checklists(id) ON DELETE CASCADE,
    version_number INTEGER NOT NULL,
    checklist_snapshot JSONB NOT NULL,
    rejected_by INTEGER REFERENCES users(id) ON DELETE
    SET NULL,
        rejection_comments TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- Index for performance when fetching history for a checklist
CREATE INDEX IF NOT EXISTS idx_qms_checklist_versions_checklist_id ON qms_checklist_versions(checklist_id);
CREATE INDEX IF NOT EXISTS idx_qms_checklist_versions_created_at ON qms_checklist_versions(created_at);
-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================