-- Users table for staff authentication
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username VARCHAR(100) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role VARCHAR(50) NOT NULL CHECK (role IN ('receptionist', 'owner')),
  full_name VARCHAR(255) NOT NULL,
  is_default_password BOOLEAN DEFAULT TRUE,
  last_password_change TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Guests table
CREATE TABLE IF NOT EXISTS guests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  id_number VARCHAR(100),
  check_in TIMESTAMP,
  check_out TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Guest rooms (support for multiple rooms per guest)
CREATE TABLE IF NOT EXISTS guest_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  guest_id UUID NOT NULL REFERENCES guests(id) ON DELETE CASCADE,
  room_number VARCHAR(50) NOT NULL,
  check_in TIMESTAMP NOT NULL,
  check_out TIMESTAMP,
  daily_rate DECIMAL(10, 2) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Transactions table (income)
CREATE TABLE IF NOT EXISTS transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  guest_id UUID NOT NULL REFERENCES guests(id) ON DELETE CASCADE,
  type VARCHAR(50) NOT NULL CHECK (type IN ('room', 'food', 'service')),
  description VARCHAR(255),
  amount DECIMAL(10, 2) NOT NULL,
  payment_method VARCHAR(50) NOT NULL CHECK (payment_method IN ('cash', 'card')),
  created_by UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  is_deleted BOOLEAN DEFAULT FALSE,
  deleted_by UUID REFERENCES users(id),
  deleted_at TIMESTAMP,
  deletion_reason VARCHAR(255)
);

-- Transaction edits audit log
CREATE TABLE IF NOT EXISTS transaction_edits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id UUID NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
  original_value JSONB NOT NULL,
  new_value JSONB NOT NULL,
  edited_by UUID NOT NULL REFERENCES users(id),
  edit_reason VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Expenses table
CREATE TABLE IF NOT EXISTS expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category VARCHAR(50) NOT NULL CHECK (category IN ('food', 'utilities', 'maintenance', 'supplies')),
  amount DECIMAL(10, 2) NOT NULL,
  description VARCHAR(255),
  vendor_name VARCHAR(255),
  created_by UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  is_deleted BOOLEAN DEFAULT FALSE,
  deleted_by UUID REFERENCES users(id),
  deleted_at TIMESTAMP,
  deletion_reason VARCHAR(255)
);

-- Expense edits audit log
CREATE TABLE IF NOT EXISTS expense_edits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_id UUID NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
  original_value JSONB NOT NULL,
  new_value JSONB NOT NULL,
  edited_by UUID NOT NULL REFERENCES users(id),
  edit_reason VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Daily summary/reconciliation
CREATE TABLE IF NOT EXISTS daily_summary (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  summary_date DATE NOT NULL UNIQUE,
  cash_total DECIMAL(10, 2) DEFAULT 0,
  card_total DECIMAL(10, 2) DEFAULT 0,
  expense_total DECIMAL(10, 2) DEFAULT 0,
  created_by UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX idx_transactions_guest_id ON transactions(guest_id);
CREATE INDEX idx_transactions_created_by ON transactions(created_by);
CREATE INDEX idx_transactions_created_at ON transactions(created_at);
CREATE INDEX idx_expenses_created_by ON expenses(created_by);
CREATE INDEX idx_expenses_created_at ON expenses(created_at);
CREATE INDEX idx_guest_rooms_guest_id ON guest_rooms(guest_id);
CREATE INDEX idx_daily_summary_date ON daily_summary(summary_date);
