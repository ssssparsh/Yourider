const express = require('express');
const router = express.Router();
const pool = require('../../database/connection');
const { hashPassword, verifyPassword, generateToken, validatePasswordStrength } = require('../utils/auth');
const { authenticate } = require('../middleware/auth');

// Login route - username and password based
router.post('/login', async (req, res) => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password required' });
    }

    const result = await pool.query(
      'SELECT * FROM users WHERE username = $1',
      [username]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const user = result.rows[0];
    const passwordValid = await verifyPassword(password, user.password_hash);

    if (!passwordValid) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const token = generateToken(user.id, user.role, user.username);

    res.json({
      token,
      user: {
        id: user.id,
        username: user.username,
        fullName: user.full_name,
        role: user.role,
        isDefaultPassword: user.is_default_password,
      },
      message: user.is_default_password ? 'Please change your password on first login' : undefined,
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get current user
router.get('/me', authenticate, async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, username, full_name, role, is_default_password FROM users WHERE id = $1',
      [req.user.userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Get user error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Change password - for first login or password reset
router.post('/change-password', authenticate, async (req, res) => {
  try {
    const { currentPassword, newPassword, confirmPassword } = req.body;

    if (!currentPassword || !newPassword || !confirmPassword) {
      return res.status(400).json({ error: 'All fields required' });
    }

    if (newPassword !== confirmPassword) {
      return res.status(400).json({ error: 'Passwords do not match' });
    }

    // Validate password strength
    const validation = validatePasswordStrength(newPassword);
    if (!validation.valid) {
      return res.status(400).json({ error: validation.message });
    }

    // Get current user
    const userResult = await pool.query(
      'SELECT * FROM users WHERE id = $1',
      [req.user.userId]
    );

    if (userResult.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    const user = userResult.rows[0];

    // Verify current password
    const passwordValid = await verifyPassword(currentPassword, user.password_hash);
    if (!passwordValid) {
      return res.status(401).json({ error: 'Current password is incorrect' });
    }

    // Hash new password
    const newPasswordHash = await hashPassword(newPassword);

    // Update password
    await pool.query(
      `UPDATE users
       SET password_hash = $1,
           is_default_password = FALSE,
           last_password_change = CURRENT_TIMESTAMP,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $2`,
      [newPasswordHash, req.user.userId]
    );

    res.json({ message: 'Password changed successfully' });
  } catch (error) {
    console.error('Change password error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Admin route to reset user password (Owner only)
router.post('/reset-password/:userId', authenticate, async (req, res) => {
  try {
    // Only owner can reset passwords
    if (req.user.role !== 'owner') {
      return res.status(403).json({ error: 'Only owner can reset passwords' });
    }

    const { userId } = req.params;
    const { newPassword } = req.body;

    if (!newPassword) {
      return res.status(400).json({ error: 'New password required' });
    }

    // Validate password strength
    const validation = validatePasswordStrength(newPassword);
    if (!validation.valid) {
      return res.status(400).json({ error: validation.message });
    }

    // Hash new password
    const passwordHash = await hashPassword(newPassword);

    // Update password
    const result = await pool.query(
      `UPDATE users
       SET password_hash = $1,
           is_default_password = TRUE,
           last_password_change = CURRENT_TIMESTAMP,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $2
       RETURNING id, username, full_name`,
      [passwordHash, userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json({
      message: 'Password reset successfully',
      user: result.rows[0],
      newPassword: newPassword,
      note: 'Please share this password with the user securely',
    });
  } catch (error) {
    console.error('Reset password error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

module.exports = router;
