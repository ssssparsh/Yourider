const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

const hashPin = async (pin) => {
  const salt = await bcrypt.genSalt(10);
  return bcrypt.hash(pin, salt);
};

const verifyPin = async (pin, pinHash) => {
  return bcrypt.compare(pin, pinHash);
};

const generateToken = (userId, role) => {
  return jwt.sign(
    { userId, role },
    process.env.JWT_SECRET,
    { expiresIn: '24h' }
  );
};

const verifyToken = (token) => {
  try {
    return jwt.verify(token, process.env.JWT_SECRET);
  } catch (error) {
    return null;
  }
};

module.exports = {
  hashPin,
  verifyPin,
  generateToken,
  verifyToken,
};
