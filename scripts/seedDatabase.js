const pool = require('../database/connection');
const { hashPin } = require('../api/utils/auth');
require('dotenv').config();

async function seedDatabase() {
  try {
    console.log('Seeding database with initial users...');

    // Create default receptionist user (PIN: 1234)
    const hashedReceptionistPin = await hashPin('1234');
    await pool.query(
      `INSERT INTO users (username, pin_hash, role, full_name)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (username) DO NOTHING`,
      ['receptionist1', hashedReceptionistPin, 'receptionist', 'Main Receptionist']
    );

    // Create default owner user (PIN: 5678)
    const hashedOwnerPin = await hashPin('5678');
    await pool.query(
      `INSERT INTO users (username, pin_hash, role, full_name)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (username) DO NOTHING`,
      ['owner', hashedOwnerPin, 'owner', 'Facility Owner']
    );

    console.log('✅ Database seeding complete!');
    console.log('\nDefault Users:');
    console.log('  Receptionist - Username: receptionist1, PIN: 1234');
    console.log('  Owner - Username: owner, PIN: 5678');

    process.exit(0);
  } catch (error) {
    console.error('Error seeding database:', error);
    process.exit(1);
  }
}

seedDatabase();
