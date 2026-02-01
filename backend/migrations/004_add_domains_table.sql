-- Create domains table for design domains
CREATE TABLE IF NOT EXISTS domains (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    code VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for domain
CREATE INDEX IF NOT EXISTS idx_domains_code ON domains(code);
CREATE INDEX IF NOT EXISTS idx_domains_is_active ON domains(is_active);

-- Insert design domains
INSERT INTO domains (name, code, description, is_active) VALUES
('Design Verification', 'DV', 'Design Verification (DV) domain for verifying chip designs', true),
('Register Transfer Level', 'RTL', 'RTL (Register Transfer Level) design domain', true),
('Design for Testability', 'DFT', 'DFT (Design for Testability) domain for testability features', true),
('Physical Design', 'PD', 'Physical design domain for layout and floorplanning', true),
('Analog Layout', 'ANALOG', 'Analog layout domain for analog circuit design', true)
ON CONFLICT (code) DO NOTHING;

-- Create trigger for updated_at
DROP TRIGGER IF EXISTS update_domains_updated_at ON domains;
CREATE TRIGGER update_domains_updated_at
    BEFORE UPDATE ON domains
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

