# Guest Facility Management App - Setup Guide

## Quick Start

### Backend Setup (Node.js + PostgreSQL)

```bash
# 1. Install dependencies
npm install

# 2. Create environment file
cp .env.example .env
# Edit .env with your database credentials

# 3. Initialize database and schema
npm run db:init

# 4. Seed default users
npm run db:seed

# 5. Start server
npm start
```

**Default Credentials:**
- Receptionist: username `receptionist1`, PIN `1234`
- Owner: username `owner`, PIN `5678`

### Mobile App Setup (React Native + Expo)

```bash
# 1. Navigate to mobile directory
cd mobile

# 2. Install dependencies
npm install

# 3. Start development server
npm start

# 4. Run on device/emulator
# iOS: npm run ios
# Android: npm run android
# Web: npm run web
```

## API Endpoints Summary

### Auth
- `POST /api/auth/login` - Login
- `GET /api/auth/me` - Current user

### Guests
- `GET /api/guests` - List all guests
- `POST /api/guests` - Create guest
- `GET /api/guests/:id` - Guest details + ledger
- `PUT /api/guests/:id` - Update guest
- `POST /api/guests/:id/rooms` - Add room

### Transactions (Income)
- `POST /api/transactions` - Record transaction
- `GET /api/transactions/guest/:id` - Guest transactions
- `PUT /api/transactions/:id` - Edit (with audit)
- `DELETE /api/transactions/:id` - Delete (with reason)

### Expenses
- `POST /api/expenses` - Record expense
- `GET /api/expenses` - List expenses
- `PUT /api/expenses/:id` - Edit (with audit)
- `DELETE /api/expenses/:id` - Delete (with reason)

### Reports
- `GET /api/reports/daily-summary` - Daily P&L
- `GET /api/reports/revenue-by-guest` - Revenue by guest
- `GET /api/reports/revenue-by-type` - Revenue by type
- `GET /api/reports/staff-activity` - Staff audit log
- `GET /api/reports/audit-trail` - Edit/delete history

## Key Features Implemented

✅ Guest profiles with identity verification
✅ Multi-room support per guest
✅ Income tracking (room, food, service)
✅ Expense management by category
✅ Complete audit trails for all edits/deletes
✅ Guest ledgers with itemized transactions
✅ Daily reconciliation summaries
✅ Revenue analytics and reports
✅ Staff activity logging
✅ Role-based access control
✅ Transaction-level database integrity

## Testing Workflow

1. **Add a Guest**
   - POST /api/guests with name, ID number
   - POST /api/guests/:id/rooms to add room

2. **Record Transactions**
   - POST /api/transactions for each charge
   - Mix cash and card payments
   - Check GET /api/transactions/guest/:id

3. **Edit & Verify Audit Trail**
   - PUT to edit a transaction with reason
   - DELETE with deletion reason
   - GET /api/reports/audit-trail to verify

4. **View Reports**
   - GET /api/reports/daily-summary
   - GET /api/reports/revenue-by-guest
   - GET /api/reports/outstanding-balances

## Database Schema

Tables: users, guests, guest_rooms, transactions, expenses, transaction_edits, expense_edits, daily_summary

All transactions are:
- Timestamped and attributed to user
- Soft-deleted (not permanently removed)
- Fully auditable (edits tracked with reasons)
- Searchable and reportable

## Configuration

Edit `.env` for:
- Database connection
- Server port
- JWT secret (change for production!)
- API URL (in mobile/src/services/api.js)

## Next Steps

1. Set up database and start backend: `npm start`
2. Start mobile app: `cd mobile && npm start`
3. Login with credentials above
4. Test full workflow: Add guest → Record transactions → View ledger
5. Check audit trails for all edits/deletes
