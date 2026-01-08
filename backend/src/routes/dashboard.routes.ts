import express from 'express';
import { pool } from '../config/database';

const router = express.Router();

// Get dashboard statistics
router.get('/stats', async (req, res) => {
  try {
    // Get total chips
    const chipsResult = await pool.query('SELECT COUNT(*) as total FROM chips');
    const totalChips = parseInt(chipsResult.rows[0].total);

    // Get chips by status
    const chipsByStatusResult = await pool.query(
      'SELECT status, COUNT(*) as count FROM chips GROUP BY status'
    );

    // Get total designs
    const designsResult = await pool.query('SELECT COUNT(*) as total FROM designs');
    const totalDesigns = parseInt(designsResult.rows[0].total);

    // Get designs by status
    const designsByStatusResult = await pool.query(
      'SELECT status, COUNT(*) as count FROM designs GROUP BY status'
    );

    // Get recent activity
    const recentChipsResult = await pool.query(
      'SELECT * FROM chips ORDER BY created_at DESC LIMIT 5'
    );

    const recentDesignsResult = await pool.query(
      'SELECT * FROM designs ORDER BY created_at DESC LIMIT 5'
    );

    res.json({
      chips: {
        total: totalChips,
        byStatus: chipsByStatusResult.rows.reduce((acc: any, row: any) => {
          acc[row.status] = parseInt(row.count);
          return acc;
        }, {})
      },
      designs: {
        total: totalDesigns,
        byStatus: designsByStatusResult.rows.reduce((acc: any, row: any) => {
          acc[row.status] = parseInt(row.count);
          return acc;
        }, {})
      },
      recent: {
        chips: recentChipsResult.rows,
        designs: recentDesignsResult.rows
      }
    });
  } catch (error: any) {
    console.error('Error fetching dashboard stats:', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;













