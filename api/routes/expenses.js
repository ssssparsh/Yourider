const express = require('express');
const router = express.Router();
const pool = require('../../database/connection');
const { authenticate } = require('../middleware/auth');

// Create a new expense
router.post('/', authenticate, async (req, res) => {
  try {
    const { category, amount, description, vendorName } = req.body;

    if (!category || !amount) {
      return res.status(400).json({ error: 'Category and amount required' });
    }

    if (!['food', 'utilities', 'maintenance', 'supplies'].includes(category)) {
      return res.status(400).json({ error: 'Invalid category' });
    }

    const result = await pool.query(
      `INSERT INTO expenses (category, amount, description, vendor_name, created_by)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [category, amount, description || null, vendorName || null, req.user.userId]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Create expense error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get all expenses
router.get('/', authenticate, async (req, res) => {
  try {
    const { startDate, endDate, category } = req.query;

    let query = `SELECT e.*, u.full_name as created_by_name
                 FROM expenses e
                 JOIN users u ON e.created_by = u.id
                 WHERE e.is_deleted = FALSE`;
    const params = [];

    if (startDate) {
      params.push(startDate);
      query += ` AND DATE(e.created_at) >= $${params.length}`;
    }

    if (endDate) {
      params.push(endDate);
      query += ` AND DATE(e.created_at) <= $${params.length}`;
    }

    if (category) {
      params.push(category);
      query += ` AND e.category = $${params.length}`;
    }

    query += ' ORDER BY e.created_at DESC';

    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (error) {
    console.error('Get expenses error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get expense by ID with edit history
router.get('/:expenseId', authenticate, async (req, res) => {
  try {
    const { expenseId } = req.params;

    const expenseResult = await pool.query(
      `SELECT e.*, u.full_name as created_by_name
       FROM expenses e
       JOIN users u ON e.created_by = u.id
       WHERE e.id = $1`,
      [expenseId]
    );

    if (expenseResult.rows.length === 0) {
      return res.status(404).json({ error: 'Expense not found' });
    }

    const editHistoryResult = await pool.query(
      `SELECT e.*, u.full_name as edited_by_name
       FROM expense_edits e
       JOIN users u ON e.edited_by = u.id
       WHERE e.expense_id = $1
       ORDER BY e.created_at ASC`,
      [expenseId]
    );

    res.json({
      expense: expenseResult.rows[0],
      editHistory: editHistoryResult.rows,
    });
  } catch (error) {
    console.error('Get expense error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Update expense with audit trail
router.put('/:expenseId', authenticate, async (req, res) => {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const { expenseId } = req.params;
    const { category, amount, description, vendorName, editReason } = req.body;

    if (!editReason) {
      return res.status(400).json({ error: 'Edit reason required' });
    }

    // Get original expense
    const originalResult = await client.query(
      'SELECT * FROM expenses WHERE id = $1',
      [expenseId]
    );

    if (originalResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Expense not found' });
    }

    const original = originalResult.rows[0];

    // Update expense
    const updateResult = await client.query(
      `UPDATE expenses
       SET category = COALESCE($1, category),
           amount = COALESCE($2, amount),
           description = COALESCE($3, description),
           vendor_name = COALESCE($4, vendor_name),
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $5
       RETURNING *`,
      [category, amount, description, vendorName, expenseId]
    );

    // Log edit to audit trail
    const newValues = updateResult.rows[0];
    await client.query(
      `INSERT INTO expense_edits (expense_id, original_value, new_value, edited_by, edit_reason)
       VALUES ($1, $2, $3, $4, $5)`,
      [
        expenseId,
        JSON.stringify({
          category: original.category,
          amount: original.amount,
          description: original.description,
          vendorName: original.vendor_name,
        }),
        JSON.stringify({
          category: newValues.category,
          amount: newValues.amount,
          description: newValues.description,
          vendorName: newValues.vendor_name,
        }),
        req.user.userId,
        editReason,
      ]
    );

    await client.query('COMMIT');
    res.json(newValues);
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Update expense error:', error);
    res.status(500).json({ error: 'Server error' });
  } finally {
    client.release();
  }
});

// Soft delete expense
router.delete('/:expenseId', authenticate, async (req, res) => {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const { expenseId } = req.params;
    const { deletionReason } = req.body;

    if (!deletionReason) {
      return res.status(400).json({ error: 'Deletion reason required' });
    }

    const result = await client.query(
      `UPDATE expenses
       SET is_deleted = TRUE,
           deleted_by = $1,
           deleted_at = CURRENT_TIMESTAMP,
           deletion_reason = $2
       WHERE id = $3
       RETURNING *`,
      [req.user.userId, deletionReason, expenseId]
    );

    if (result.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Expense not found' });
    }

    // Log deletion to audit trail
    await client.query(
      `INSERT INTO expense_edits (expense_id, original_value, new_value, edited_by, edit_reason)
       VALUES ($1, $2, $3, $4, $5)`,
      [
        expenseId,
        JSON.stringify({ deleted: false }),
        JSON.stringify({ deleted: true, reason: deletionReason }),
        req.user.userId,
        `Deletion: ${deletionReason}`,
      ]
    );

    await client.query('COMMIT');
    res.json({ message: 'Expense deleted', expense: result.rows[0] });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Delete expense error:', error);
    res.status(500).json({ error: 'Server error' });
  } finally {
    client.release();
  }
});

// Get expense summary
router.get('/summary/category', authenticate, async (req, res) => {
  try {
    const { startDate, endDate } = req.query;

    let query = `SELECT category, SUM(amount) as total, COUNT(*) as count
                 FROM expenses
                 WHERE is_deleted = FALSE`;
    const params = [];

    if (startDate) {
      params.push(startDate);
      query += ` AND DATE(created_at) >= $${params.length}`;
    }

    if (endDate) {
      params.push(endDate);
      query += ` AND DATE(created_at) <= $${params.length}`;
    }

    query += ' GROUP BY category ORDER BY total DESC';

    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (error) {
    console.error('Get expense summary error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

module.exports = router;
