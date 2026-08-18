const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  database: 'postgres', // Connect to default database first
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

async function initializeDatabase() {
  const client = await pool.connect();

  try {
    // Create database if it doesn't exist
    console.log('Creating database if not exists...');
    await client.query(`CREATE DATABASE ${process.env.DB_NAME};`);
    console.log(`Database ${process.env.DB_NAME} created successfully`);
  } catch (error) {
    if (error.message.includes('already exists')) {
      console.log(`Database ${process.env.DB_NAME} already exists`);
    } else {
      throw error;
    }
  } finally {
    await client.end();
  }

  // Connect to the new database
  const dbPool = new Pool({
    host: process.env.DB_HOST,
    port: process.env.DB_PORT,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
  });

  const dbClient = await dbPool.connect();

  try {
    console.log('\nInitializing schema...');

    // Read and execute schema file
    const schemaPath = path.join(__dirname, '../database/migrations/001_initial_schema.sql');
    const schema = fs.readFileSync(schemaPath, 'utf8');

    // Split by semicolon and execute each statement
    const statements = schema.split(';').filter(stmt => stmt.trim());

    for (const statement of statements) {
      if (statement.trim()) {
        await dbClient.query(statement);
      }
    }

    console.log('Schema initialized successfully');
  } catch (error) {
    console.error('Error initializing schema:', error);
    throw error;
  } finally {
    await dbClient.end();
    await dbPool.end();
  }
}

initializeDatabase()
  .then(() => {
    console.log('\n✅ Database initialization complete!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n❌ Database initialization failed:', error);
    process.exit(1);
  });
