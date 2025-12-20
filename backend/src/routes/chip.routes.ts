import express from 'express';
import { pool } from '../config/database';

const router = express.Router();

// Get all chips
router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM chips ORDER BY created_at DESC'
    );
    res.json(result.rows);
  } catch (error: any) {
    console.error('Error fetching chips:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get chip by ID
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query('SELECT * FROM chips WHERE id = $1', [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Chip not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error: any) {
    console.error('Error fetching chip:', error);
    res.status(500).json({ error: error.message });
  }
});

// Create new chip
router.post('/', async (req, res) => {
  try {
    const { name, description, architecture, process_node, status } = req.body;
    const userId = (req as any).user?.id || null;
    
    const result = await pool.query(
      `INSERT INTO chips (name, description, architecture, process_node, status, created_by)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [name, description, architecture, process_node, status || 'design', userId]
    );
    
    res.status(201).json(result.rows[0]);
  } catch (error: any) {
    console.error('Error creating chip:', error);
    res.status(500).json({ error: error.message });
  }
});

// Update chip
router.put('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { name, description, architecture, process_node, status } = req.body;
    const userId = (req as any).user?.id || null;
    
    const result = await pool.query(
      `UPDATE chips 
       SET name = $1, description = $2, architecture = $3, 
           process_node = $4, status = $5, updated_at = NOW(), updated_by = $7
       WHERE id = $6
       RETURNING *`,
      [name, description, architecture, process_node, status, id, userId]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Chip not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error: any) {
    console.error('Error updating chip:', error);
    res.status(500).json({ error: error.message });
  }
});

// Delete chip
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query('DELETE FROM chips WHERE id = $1 RETURNING *', [id]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Chip not found' });
    }
    
    res.json({ message: 'Chip deleted successfully' });
  } catch (error: any) {
    console.error('Error deleting chip:', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;

