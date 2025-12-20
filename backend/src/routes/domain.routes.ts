import express from 'express';
import { pool } from '../config/database';

const router = express.Router();

// Get all domains
router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM domains ORDER BY name ASC'
    );
    res.json(result.rows);
  } catch (error: any) {
    console.error('Error fetching domains:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get domain by code (must be before /:id route)
router.get('/code/:code', async (req, res) => {
  try {
    const { code } = req.params;
    const result = await pool.query('SELECT * FROM domains WHERE code = $1', [code.toUpperCase()]);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Domain not found' });
    }
    
    res.json(result.rows[0]);
  } catch (error: any) {
    console.error('Error fetching domain by code:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get designs by domain
router.get('/:id/designs', async (req, res) => {
  try {
    const { id } = req.params;
    const result = await pool.query(
      `SELECT d.*, c.name as chip_name
       FROM designs d
       LEFT JOIN chips c ON d.chip_id = c.id
       WHERE d.domain_id = $1
       ORDER BY d.created_at DESC`,
      [id]
    );
    res.json(result.rows);
  } catch (error: any) {
    console.error('Error fetching designs by domain:', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;

