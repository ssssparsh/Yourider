const express = require('express');
const router = express.Router();
const pool = require('../../database/connection');
const { authenticate } = require('../middleware/auth');

// Daily P&L report
router.get('/daily-summary', authenticate, async (req, res) => {
  try {
    const { date } = req.query;

    if (!date) {
      return res.status(400).json({ error: 'Date required' });
    }

    // Get cash transactions
    const cashResult = await pool.query(
      `SELECT SUM(amount) as total
       FROM transactions
       WHERE DATE(created_at) = $1 AND payment_method = 'cash' AND is_deleted = FALSE`,
      [date]
    );

    // Get card transactions
    const cardResult = await pool.query(
      `SELECT SUM(amount) as total
       FROM transactions
       WHERE DATE(created_at) = $1 AND payment_method = 'card' AND is_deleted = FALSE`,
      [date]
    );

    // Get expenses
    const expenseResult = await pool.query(
      `SELECT SUM(amount) as total
       FROM expenses
       WHERE DATE(created_at) = $1 AND is_deleted = FALSE`,
      [date]
    );

    // Get transaction breakdown by type
    const typeBreakdownResult = await pool.query(
      `SELECT type, SUM(amount) as total, COUNT(*) as count
       FROM transactions
       WHERE DATE(created_at) = $1 AND is_deleted = FALSE
       GROUP BY type`,
      [date]
    );

    const cashTotal = cashResult.rows[0]?.total || 0;
    const cardTotal = cardResult.rows[0]?.total || 0;
    const expenseTotal = expenseResult.rows[0]?.total || 0;
    const grossIncome = cashTotal + cardTotal;
    const netIncome = grossIncome - expenseTotal;

    res.json({
      date,
      income: {
        cash: parseFloat(cashTotal),
        card: parseFloat(cardTotal),
        total: parseFloat(grossIncome),
      },
      expenses: parseFloat(expenseTotal),
      netIncome: parseFloat(netIncome),
      typeBreakdown: typeBreakdownResult.rows,
    });
  } catch (error) {
    console.error('Daily summary error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Revenue by guest report
router.get('/revenue-by-guest', authenticate, async (req, res) => {
  try {
    const { startDate, endDate } = req.query;

    let query = `SELECT
                  g.id, g.name, g.id_number,
                  SUM(CASE WHEN t.is_deleted = FALSE THEN t.amount ELSE 0 END) as total_revenue,
                  COUNT(CASE WHEN t.is_deleted = FALSE THEN 1 END) as transaction_count
                 FROM guests g
                 LEFT JOIN transactions t ON g.id = t.guest_id`;

    const params = [];

    if (startDate && endDate) {
      params.push(startDate, endDate);
      query += ` WHERE DATE(t.created_at) BETWEEN $1 AND $2`;
    }

    query += ` GROUP BY g.id, g.name, g.id_number
               ORDER BY total_revenue DESC`;

    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (error) {
    console.error('Revenue by guest error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Revenue by service type report
router.get('/revenue-by-type', authenticate, async (req, res) => {
  try {
    const { startDate, endDate } = req.query;

    let query = `SELECT
                  type,
                  SUM(CASE WHEN is_deleted = FALSE THEN amount ELSE 0 END) as total,
                  COUNT(CASE WHEN is_deleted = FALSE THEN 1 END) as count
                 FROM transactions`;

    const params = [];

    if (startDate && endDate) {
      params.push(startDate, endDate);
      query += ` WHERE DATE(created_at) BETWEEN $1 AND $2`;
    }

    query += ` GROUP BY type ORDER BY total DESC`;

    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (error) {
    console.error('Revenue by type error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Staff activity audit log
router.get('/staff-activity', authenticate, async (req, res) => {
  try {
    const { userId, startDate, endDate } = req.query;

    let query = `SELECT
                  u.id, u.username, u.full_name,
                  COUNT(*) as transactions_created,
                  SUM(CASE WHEN t.is_deleted = FALSE THEN t.amount ELSE 0 END) as total_amount
                 FROM users u
                 LEFT JOIN transactions t ON u.id = t.created_by`;

    const params = [];

    if (userId) {
      params.push(userId);
      query += ` WHERE u.id = $${params.length}`;
    }

    if (startDate && endDate) {
      if (userId) {
        params.push(startDate, endDate);
        query += ` AND DATE(t.created_at) BETWEEN $${params.length - 1} AND $${params.length}`;
      } else {
        params.push(startDate, endDate);
        query += ` WHERE DATE(t.created_at) BETWEEN $${params.length - 1} AND $${params.length}`;
      }
    }

    query += ` GROUP BY u.id, u.username, u.full_name
               ORDER BY transactions_created DESC`;

    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (error) {
    console.error('Staff activity error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get edit/delete audit trail
router.get('/audit-trail', authenticate, async (req, res) => {
  try {
    const { entityType, entityId, startDate, endDate } = req.query;

    if (!entityType) {
      return res.status(400).json({ error: 'Entity type (transaction/expense) required' });
    }

    let query = '';
    const params = [];

    if (entityType === 'transaction') {
      query = `SELECT
                e.id, e.transaction_id as entity_id, 'transaction' as type,
                e.original_value, e.new_value, e.edit_reason,
                u.full_name as edited_by, e.created_at
               FROM transaction_edits e
               JOIN users u ON e.edited_by = u.id`;

      if (entityId) {
        params.push(entityId);
        query += ` WHERE e.transaction_id = $${params.length}`;
      }
    } else if (entityType === 'expense') {
      query = `SELECT
                e.id, e.expense_id as entity_id, 'expense' as type,
                e.original_value, e.new_value, e.edit_reason,
                u.full_name as edited_by, e.created_at
               FROM expense_edits e
               JOIN users u ON e.edited_by = u.id`;

      if (entityId) {
        params.push(entityId);
        query += ` WHERE e.expense_id = $${params.length}`;
      }
    }

    if (startDate && endDate) {
      const startIdx = params.length + 1;
      params.push(startDate, endDate);
      query += `${entityId ? ' AND' : ' WHERE'} DATE(e.created_at) BETWEEN $${startIdx} AND $${startIdx + 1}`;
    }

    query += ' ORDER BY e.created_at DESC';

    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (error) {
    console.error('Audit trail error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Guest ledger summary (who owes money)
router.get('/outstanding-balances', authenticate, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT
        g.id, g.name, g.id_number, g.check_in, g.check_out,
        SUM(CASE WHEN t.is_deleted = FALSE THEN t.amount ELSE 0 END) as total_owed,
        COUNT(CASE WHEN t.is_deleted = FALSE THEN 1 END) as transaction_count
       FROM guests g
       LEFT JOIN transactions t ON g.id = t.guest_id
       GROUP BY g.id, g.name, g.id_number, g.check_in, g.check_out
       HAVING SUM(CASE WHEN t.is_deleted = FALSE THEN t.amount ELSE 0 END) > 0
       ORDER BY total_owed DESC`
    );

    res.json(result.rows);
  } catch (error) {
    console.error('Outstanding balances error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

module.exports = router;
