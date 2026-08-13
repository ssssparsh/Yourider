const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

// Hash password for secure storage
const hashPassword = async (password) => {
  const salt = await bcrypt.genSalt(10);
  return bcrypt.hash(password, salt);
};

// Verify password against hash
const verifyPassword = async (password, passwordHash) => {
  return bcrypt.compare(password, passwordHash);
};

// Generate JWT token
const generateToken = (userId, role, username) => {
  return jwt.sign(
    { userId, role, username },
    process.env.JWT_SECRET,
    { expiresIn: '24h' }
  );
};

// Verify JWT token
const verifyToken = (token) => {
  try {
    return jwt.verify(token, process.env.JWT_SECRET);
  } catch (error) {
    return null;
  }
};

// Validate password strength
const validatePasswordStrength = (password) => {
  if (password.length < 6) {
    return { valid: false, message: 'Password must be at least 6 characters' };
  }
  if (!/[A-Z]/.test(password)) {
    return { valid: false, message: 'Password must contain uppercase letter' };
  }
  if (!/[0-9]/.test(password)) {
    return { valid: false, message: 'Password must contain number' };
  }
  return { valid: true };
};

module.exports = {
  hashPassword,
  verifyPassword,
  generateToken,
  verifyToken,
  validatePasswordStrength,
};
