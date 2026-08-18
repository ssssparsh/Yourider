const pool = require('../database/connection');
const { hashPassword } = require('../api/utils/auth');
require('dotenv').config();

async function seedDatabase() {
  try {
    console.log('Seeding database with initial users...');

    // Create default receptionist user (password: Reception@123)
    const receptionistPassword = 'Reception@123';
    const hashedReceptionistPassword = await hashPassword(receptionistPassword);
    await pool.query(
      `INSERT INTO users (username, password_hash, role, full_name, is_default_password)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (username) DO NOTHING`,
      ['receptionist1', hashedReceptionistPassword, 'receptionist', 'Main Receptionist', true]
    );

    // Create second receptionist user (password: Reception@456)
    const receptionist2Password = 'Reception@456';
    const hashedReceptionist2Password = await hashPassword(receptionist2Password);
    await pool.query(
      `INSERT INTO users (username, password_hash, role, full_name, is_default_password)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (username) DO NOTHING`,
      ['receptionist2', hashedReceptionist2Password, 'receptionist', 'Assistant Receptionist', true]
    );

    // Create default owner user (password: Owner@5678)
    const ownerPassword = 'Owner@5678';
    const hashedOwnerPassword = await hashPassword(ownerPassword);
    await pool.query(
      `INSERT INTO users (username, password_hash, role, full_name, is_default_password)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (username) DO NOTHING`,
      ['owner', hashedOwnerPassword, 'owner', 'Facility Owner', true]
    );

    console.log('✅ Database seeding complete!\n');
    console.log('═══════════════════════════════════════════════════════════════');
    console.log('DEFAULT CREDENTIALS - CHANGE ON FIRST LOGIN!');
    console.log('═══════════════════════════════════════════════════════════════\n');
    console.log('📱 Receptionist 1:');
    console.log('   Username: receptionist1');
    console.log('   Password: Reception@123\n');
    console.log('📱 Receptionist 2:');
    console.log('   Username: receptionist2');
    console.log('   Password: Reception@456\n');
    console.log('👨‍💼 Owner/Manager:');
    console.log('   Username: owner');
    console.log('   Password: Owner@5678\n');
    console.log('⚠️  IMPORTANT:');
    console.log('   - Each user MUST change password on first login');
    console.log('   - Password must be: Min 6 chars, 1 uppercase, 1 number');
    console.log('   - Owner can reset receptionist passwords if needed');
    console.log('═══════════════════════════════════════════════════════════════\n');

    process.exit(0);
  } catch (error) {
    console.error('Error seeding database:', error);
    process.exit(1);
  }
}

seedDatabase();
