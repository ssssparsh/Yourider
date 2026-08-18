# Installation Instructions - Guest Facility Management App

## Quick Overview

Your app is now ready with **username/password authentication** instead of PIN-based login. Each of your 2 receptionists gets a unique username and password that they can change on first login.

## Step 1: Install and Setup Backend

### Prerequisites
- Node.js v14+ installed
- PostgreSQL v12+ installed and running
- Terminal/Command Line access

### Installation

```bash
# Navigate to project root
cd /path/to/Yourider

# Install dependencies
npm install

# Create environment file
cp .env.example .env

# Edit .env with your database credentials
# Example:
# DB_HOST=localhost
# DB_PORT=5432
# DB_NAME=guest_facility_db
# DB_USER=postgres
# DB_PASSWORD=your_postgres_password
```

### Initialize Database

```bash
# Create database and schema
npm run db:init

# Seed default users
npm run db:seed
```

You'll see output like:
```
✅ Database seeding complete!

═══════════════════════════════════════════════════════════════
DEFAULT CREDENTIALS - CHANGE ON FIRST LOGIN!
═══════════════════════════════════════════════════════════════

📱 Receptionist 1:
   Username: receptionist1
   Password: Reception@123

📱 Receptionist 2:
   Username: receptionist2
   Password: Reception@456

👨‍💼 Owner/Manager:
   Username: owner
   Password: Owner@5678
```

### Start Backend Server

```bash
npm start
# Server runs on http://localhost:5000
```

## Step 2: Install and Setup Mobile App

### Prerequisites
- Node.js v14+ installed
- Expo CLI: `npm install -g expo-cli`
- iOS Simulator (Mac) or Android Emulator (Windows/Mac/Linux)
- Or physical Android/iOS device with Expo Go app

### Installation

```bash
# Navigate to mobile directory
cd mobile

# Install dependencies
npm install

# Start Expo development server
npm start
```

### Run on Device/Emulator

**iOS (Mac only):**
```bash
npm run ios
```

**Android (Windows/Mac/Linux):**
```bash
npm run android
```

**Web (testing only):**
```bash
npm run web
```

## Step 3: First Login - Receptionist 1

### Login Screen

When the app opens, you'll see the login screen:

```
Guest Facility Manager
Secure Income & Expense Tracking

Username: [receptionist1]
Password: [Reception@123]

[Login Button]

📋 Default Credentials
Receptionist 1: receptionist1 / Reception@123
Receptionist 2: receptionist2 / Reception@456
Owner: owner / Owner@5678

🔐 Password Requirements
✓ Minimum 6 characters
✓ At least 1 uppercase letter
✓ At least 1 number
```

### First Login Steps

1. **Enter username**: `receptionist1`
2. **Enter password**: `Reception@123`
3. **Tap Login button**
4. **Security Alert appears**: "You must change your default password"
5. **Tap "Change Now"** → Goes to Change Password screen

### Change Password Screen

Fill in these fields:

```
Current Password: [Reception@123]
New Password: [YourNewPassword]
Confirm Password: [YourNewPassword]

[Change Password Button]
```

**Choose a strong password:**
- Min 6 characters
- Include 1 uppercase letter
- Include 1 number
- Examples: `Guest2024Secure`, `MyPassword@1`, `Facility@2024`

5. **Tap "Change Password"**
6. **Success alert** → Returns to home screen
7. **Future logins** → Use new password

## Step 4: Second Receptionist Setup

### Same Process as Above

1. Start mobile app (or login as new user)
2. **Login with:**
   - Username: `receptionist2`
   - Password: `Reception@456`
3. **Security alert** → Tap "Change Now"
4. **Enter new password** → Confirm
5. **Success** → Returns to home screen

## Step 5: Owner/Manager Setup

### Login as Owner

1. **Login with:**
   - Username: `owner`
   - Password: `Owner@5678`
2. **Security alert** → Tap "Change Now"
3. **Enter new password** → Confirm
4. **Success** → Can now manage system

### Owner Capabilities

- View complete financial reports
- See staff activity logs
- View edit/delete audit trails
- Reset receptionist passwords if needed

## Step 6: Configure API Connection

### If testing on physical device:

Edit `mobile/src/services/api.js`:

```javascript
// Change this:
const API_URL = 'http://localhost:5000/api'; // localhost won't work on device

// To your computer's IP address:
const API_URL = 'http://192.168.X.X:5000/api'; // Replace X.X with your IP
```

**Find your computer's IP:**
- **Windows:** Open CMD, type `ipconfig`, look for IPv4 Address
- **Mac/Linux:** Open Terminal, type `ifconfig`, look for inet address

## Typical Setup Workflow

### Day 1: Initial Setup
```
1. Owner installs backend on office computer
   └─ npm run db:init
   └─ npm run db:seed
   └─ npm start

2. Owner installs app on personal phone
   └─ Login: owner / Owner@5678
   └─ Change password to secure password

3. Receptionist 1 installs app
   └─ Login: receptionist1 / Reception@123
   └─ Change password to secure password

4. Receptionist 2 installs app
   └─ Login: receptionist2 / Reception@456
   └─ Change password to secure password
```

### Day 2+: Normal Operation
```
- All users login with their own username/password
- Can record transactions, view guest ledgers
- Owner can view reports and audit trails
- All data synced to central database
```

## Testing the System

### Basic Flow
1. **Add Guest** (Receptionist)
   - Home → Add Guest
   - Enter name and ID number
   - Assign room with dates and rate

2. **Record Transaction** (Receptionist)
   - Home → Add Transaction
   - Select guest
   - Choose type (room/food/service)
   - Enter amount
   - Select payment method (cash/card)
   - Submit

3. **View Ledger** (Receptionist)
   - Guests → Tap guest name
   - See all their transactions
   - See total owed

4. **Check Reports** (Owner)
   - Reports → Daily P&L
   - Reports → Revenue by guest
   - Reports → Staff activity

## Troubleshooting

### "Cannot connect to server"
- ✅ Check backend is running: `npm start`
- ✅ Check API_URL is correct in mobile/src/services/api.js
- ✅ Check device can reach computer (same WiFi)

### "Invalid credentials"
- ✅ Check username spelling (case-sensitive)
- ✅ Check password spelling
- ✅ Use default credentials from database seed output

### "Must change password" keeps appearing
- ✅ Complete password change on first login
- ✅ New password must be at least 6 chars, 1 uppercase, 1 number
- ✅ Confirm password must match new password

### Forgot password
- ✅ Owner can reset it using API
- ✅ GET /api/reports/staff-activity to verify login

### App won't start
- ✅ Check Node.js installed: `node --version`
- ✅ Check npm installed: `npm --version`
- ✅ Delete node_modules and reinstall: `rm -rf node_modules && npm install`

## Production Deployment Checklist

Before deploying to real users:

- [ ] Change all default passwords
- [ ] Update database credentials
- [ ] Set JWT_SECRET to random string: `openssl rand -base64 32`
- [ ] Use HTTPS for backend (install SSL certificate)
- [ ] Update API_URL to use HTTPS
- [ ] Set NODE_ENV=production
- [ ] Enable database backups
- [ ] Document owner's password (secure location)
- [ ] Test full workflow with all users
- [ ] Backup database before first day

## Support & Documentation

- **Setup Guide:** See SETUP_GUIDE.md
- **Authentication Details:** See AUTHENTICATION_GUIDE.md
- **Implementation Summary:** See IMPLEMENTATION_SUMMARY.md
- **API Endpoints:** See SETUP_GUIDE.md

---

**Questions?** Check the relevant guide file or review the error messages in the app/terminal logs.

**Ready?** Proceed to testing the system workflow!
