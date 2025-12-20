-- Create chips table
CREATE TABLE IF NOT EXISTS chips (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    architecture VARCHAR(100),
    process_node VARCHAR(50),
    status VARCHAR(50) DEFAULT 'design',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create designs table
CREATE TABLE IF NOT EXISTS designs (
    id SERIAL PRIMARY KEY,
    chip_id INTEGER REFERENCES chips(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    design_type VARCHAR(100),
    status VARCHAR(50) DEFAULT 'draft',
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_chips_status ON chips(status);
CREATE INDEX IF NOT EXISTS idx_designs_chip_id ON designs(chip_id);
CREATE INDEX IF NOT EXISTS idx_designs_status ON designs(status);

-- Note: Sample data removed. Use the API endpoints to create chips and designs.

