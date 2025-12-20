import express from 'express';
import { pool } from '../config/database';

const router = express.Router();

// Get all designs
router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT d.*, c.name as chip_name 
       FROM designs d
       LEFT JOIN chips c ON d.chip_id = c.id
       ORDER BY d.created_at DESC`
    );
    res.json(result.rows);
  } catch (error: any) {
    console.error('Error fetching designs:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get design by ID
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query(
      `SELECT d.*, c.name as chip_name 
       FROM designs d
       LEFT JOIN chips c ON d.chip_id = c.id
       WHERE d.id = $1`,
      [id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Design not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error: any) {
    console.error('Error fetching design:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get designs by chip ID
router.get('/chip/:chipId', async (req, res) => {
  try {
    const { chipId } = req.params;
    const result = await pool.query(
      'SELECT * FROM designs WHERE chip_id = $1 ORDER BY created_at DESC',
      [chipId]
    );
    res.json(result.rows);
  } catch (error: any) {
    console.error('Error fetching designs by chip:', error);
    res.status(500).json({ error: error.message });
  }
});

// Create new design
router.post('/', async (req, res) => {
  try {
    const { chip_id, name, description, design_type, status, metadata } = req.body;
    const userId = (req as any).user?.id || null;
    
    const result = await pool.query(
      `INSERT INTO designs (chip_id, name, description, design_type, status, metadata, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING *`,
      [chip_id, name, description, design_type, status || 'draft', JSON.stringify(metadata || {}), userId]
    );
    
    res.status(201).json(result.rows[0]);
  } catch (error: any) {
    console.error('Error creating design:', error);
    res.status(500).json({ error: error.message });
  }
});

// Update design
router.put('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { name, description, design_type, status, metadata } = req.body;
    const userId = (req as any).user?.id || null;
    
    const result = await pool.query(
      `UPDATE designs 
       SET name = $1, description = $2, design_type = $3, 
           status = $4, metadata = $5, updated_at = NOW(), updated_by = $7
       WHERE id = $6
       RETURNING *`,
      [name, description, design_type, status, JSON.stringify(metadata || {}), id, userId]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Design not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error: any) {
    console.error('Error updating design:', error);
    res.status(500).json({ error: error.message });
  }
});

// Delete design
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query('DELETE FROM designs WHERE id = $1 RETURNING *', [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Design not found' });
    }
    
    res.json({ message: 'Design deleted successfully' });
  } catch (error: any) {
    console.error('Error deleting design:', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;

