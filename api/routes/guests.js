const express = require('express');
const router = express.Router();
const pool = require('../../database/connection');
const { authenticate } = require('../middleware/auth');

// Create a new guest
router.post('/', authenticate, async (req, res) => {
  try {
    const { name, idNumber, checkIn, checkOut } = req.body;

    if (!name || !idNumber) {
      return res.status(400).json({ error: 'Name and ID number required' });
    }

    const result = await pool.query(
      `INSERT INTO guests (name, id_number, check_in, check_out)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [name, idNumber, checkIn || null, checkOut || null]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Create guest error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get all guests
router.get('/', authenticate, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT g.*, COUNT(gr.id) as room_count
       FROM guests g
       LEFT JOIN guest_rooms gr ON g.id = gr.guest_id
       GROUP BY g.id
       ORDER BY g.created_at DESC`
    );

    res.json(result.rows);
  } catch (error) {
    console.error('Get guests error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get guest by ID with full details
router.get('/:guestId', authenticate, async (req, res) => {
  try {
    const { guestId } = req.params;

    const guestResult = await pool.query(
      'SELECT * FROM guests WHERE id = $1',
      [guestId]
    );

    if (guestResult.rows.length === 0) {
      return res.status(404).json({ error: 'Guest not found' });
    }

    const guest = guestResult.rows[0];

    // Get rooms
    const roomsResult = await pool.query(
      'SELECT * FROM guest_rooms WHERE guest_id = $1 ORDER BY check_in DESC',
      [guestId]
    );

    // Get transactions
    const transactionsResult = await pool.query(
      `SELECT t.*, u.full_name as created_by_name
       FROM transactions t
       JOIN users u ON t.created_by = u.id
       WHERE t.guest_id = $1 AND t.is_deleted = FALSE
       ORDER BY t.created_at DESC`,
      [guestId]
    );

    res.json({
      ...guest,
      rooms: roomsResult.rows,
      transactions: transactionsResult.rows,
    });
  } catch (error) {
    console.error('Get guest details error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Update guest
router.put('/:guestId', authenticate, async (req, res) => {
  try {
    const { guestId } = req.params;
    const { name, idNumber, checkIn, checkOut } = req.body;

    const result = await pool.query(
      `UPDATE guests
       SET name = COALESCE($1, name),
           id_number = COALESCE($2, id_number),
           check_in = COALESCE($3, check_in),
           check_out = COALESCE($4, check_out),
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $5
       RETURNING *`,
      [name, idNumber, checkIn, checkOut, guestId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Guest not found' });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Update guest error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Add room to guest
router.post('/:guestId/rooms', authenticate, async (req, res) => {
  try {
    const { guestId } = req.params;
    const { roomNumber, checkIn, checkOut, dailyRate } = req.body;

    if (!roomNumber || !checkIn || !dailyRate) {
      return res.status(400).json({ error: 'Room number, check-in, and daily rate required' });
    }

    const result = await pool.query(
      `INSERT INTO guest_rooms (guest_id, room_number, check_in, check_out, daily_rate)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [guestId, roomNumber, checkIn, checkOut || null, dailyRate]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Add room error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

module.exports = router;
