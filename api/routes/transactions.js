const express = require('express');
const router = express.Router();
const pool = require('../../database/connection');
const { authenticate } = require('../middleware/auth');

// Create a new transaction
router.post('/', authenticate, async (req, res) => {
  try {
    const { guestId, type, description, amount, paymentMethod } = req.body;

    if (!guestId || !type || !amount || !paymentMethod) {
      return res.status(400).json({ error: 'Guest ID, type, amount, and payment method required' });
    }

    if (!['room', 'food', 'service'].includes(type)) {
      return res.status(400).json({ error: 'Invalid transaction type' });
    }

    if (!['cash', 'card'].includes(paymentMethod)) {
      return res.status(400).json({ error: 'Invalid payment method' });
    }

    const result = await pool.query(
      `INSERT INTO transactions (guest_id, type, description, amount, payment_method, created_by)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [guestId, type, description || null, amount, paymentMethod, req.user.userId]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Create transaction error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get all transactions for a guest
router.get('/guest/:guestId', authenticate, async (req, res) => {
  try {
    const { guestId } = req.params;

    const result = await pool.query(
      `SELECT t.*, u.full_name as created_by_name
       FROM transactions t
       JOIN users u ON t.created_by = u.id
       WHERE t.guest_id = $1
       ORDER BY t.created_at DESC`,
      [guestId]
    );

    // Calculate balance
    const balance = result.rows.reduce((sum, t) => {
      return t.is_deleted ? sum : sum + parseFloat(t.amount);
    }, 0);

    res.json({
      transactions: result.rows,
      totalCharged: balance,
    });
  } catch (error) {
    console.error('Get guest transactions error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get transaction by ID with edit history
router.get('/:transactionId', authenticate, async (req, res) => {
  try {
    const { transactionId } = req.params;

    const transactionResult = await pool.query(
      `SELECT t.*, u.full_name as created_by_name
       FROM transactions t
       JOIN users u ON t.created_by = u.id
       WHERE t.id = $1`,
      [transactionId]
    );

    if (transactionResult.rows.length === 0) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    const editHistoryResult = await pool.query(
      `SELECT e.*, u.full_name as edited_by_name
       FROM transaction_edits e
       JOIN users u ON e.edited_by = u.id
       WHERE e.transaction_id = $1
       ORDER BY e.created_at ASC`,
      [transactionId]
    );

    res.json({
      transaction: transactionResult.rows[0],
      editHistory: editHistoryResult.rows,
    });
  } catch (error) {
    console.error('Get transaction error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Update transaction with audit trail
router.put('/:transactionId', authenticate, async (req, res) => {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const { transactionId } = req.params;
    const { type, description, amount, paymentMethod, editReason } = req.body;

    if (!editReason) {
      return res.status(400).json({ error: 'Edit reason required' });
    }

    // Get original transaction
    const originalResult = await client.query(
      'SELECT * FROM transactions WHERE id = $1',
      [transactionId]
    );

    if (originalResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Transaction not found' });
    }

    const original = originalResult.rows[0];

    // Update transaction
    const updateResult = await client.query(
      `UPDATE transactions
       SET type = COALESCE($1, type),
           description = COALESCE($2, description),
           amount = COALESCE($3, amount),
           payment_method = COALESCE($4, payment_method),
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $5
       RETURNING *`,
      [type, description, amount, paymentMethod, transactionId]
    );

    // Log edit to audit trail
    const newValues = updateResult.rows[0];
    await client.query(
      `INSERT INTO transaction_edits (transaction_id, original_value, new_value, edited_by, edit_reason)
       VALUES ($1, $2, $3, $4, $5)`,
      [
        transactionId,
        JSON.stringify({
          type: original.type,
          description: original.description,
          amount: original.amount,
          paymentMethod: original.payment_method,
        }),
        JSON.stringify({
          type: newValues.type,
          description: newValues.description,
          amount: newValues.amount,
          paymentMethod: newValues.payment_method,
        }),
        req.user.userId,
        editReason,
      ]
    );

    await client.query('COMMIT');
    res.json(newValues);
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Update transaction error:', error);
    res.status(500).json({ error: 'Server error' });
  } finally {
    client.release();
  }
});

// Soft delete transaction
router.delete('/:transactionId', authenticate, async (req, res) => {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const { transactionId } = req.params;
    const { deletionReason } = req.body;

    if (!deletionReason) {
      return res.status(400).json({ error: 'Deletion reason required' });
    }

    const result = await client.query(
      `UPDATE transactions
       SET is_deleted = TRUE,
           deleted_by = $1,
           deleted_at = CURRENT_TIMESTAMP,
           deletion_reason = $2
       WHERE id = $3
       RETURNING *`,
      [req.user.userId, deletionReason, transactionId]
    );

    if (result.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Transaction not found' });
    }

    // Log deletion to audit trail
    await client.query(
      `INSERT INTO transaction_edits (transaction_id, original_value, new_value, edited_by, edit_reason)
       VALUES ($1, $2, $3, $4, $5)`,
      [
        transactionId,
        JSON.stringify({ deleted: false }),
        JSON.stringify({ deleted: true, reason: deletionReason }),
        req.user.userId,
        `Deletion: ${deletionReason}`,
      ]
    );

    await client.query('COMMIT');
    res.json({ message: 'Transaction deleted', transaction: result.rows[0] });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Delete transaction error:', error);
    res.status(500).json({ error: 'Server error' });
  } finally {
    client.release();
  }
});

// Get all transactions for a date range
router.get('/report/daily', authenticate, async (req, res) => {
  try {
    const { startDate, endDate } = req.query;

    const result = await pool.query(
      `SELECT
        DATE(t.created_at) as date,
        t.payment_method,
        SUM(CASE WHEN t.is_deleted = FALSE THEN t.amount ELSE 0 END) as total
       FROM transactions t
       WHERE DATE(t.created_at) BETWEEN $1 AND $2
       GROUP BY DATE(t.created_at), t.payment_method
       ORDER BY date DESC`,
      [startDate, endDate]
    );

    res.json(result.rows);
  } catch (error) {
    console.error('Get daily report error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

module.exports = router;
