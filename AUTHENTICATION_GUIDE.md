# Authentication & Security Guide

## Overview

The Guest Facility Management App uses **username and password authentication** (not PIN-based) to ensure secure access for your 2 receptionists and owner account.

## Default Credentials

After database initialization, the following **default credentials** are created:

### Receptionist 1
```
Username: receptionist1
Password: Reception@123
```

### Receptionist 2
```
Username: receptionist2
Password: Reception@456
```

### Owner/Manager
```
Username: owner
Password: Owner@5678
```

## Password Requirements

All passwords must meet these security standards:
- ✅ Minimum 6 characters
- ✅ At least 1 uppercase letter
- ✅ At least 1 number

Example of valid passwords:
```
MyPassword123
Secure@Pass99
Guest2024Room
```

## First Login - Mandatory Password Change

When a user logs in with default credentials for the first time:

1. **Login Screen** - User enters username and default password
2. **First Login Alert** - App notifies: "You must change your default password"
3. **Redirect to Change Password** - User is prompted to set a new password
4. **Password Change Form** - Requires:
   - Current password (default password)
   - New password (must meet requirements)
   - Confirm new password (must match)
5. **Success** - User returns to home screen with new secure password

**⚠️ IMPORTANT:** Users CANNOT access the app fully until they change their default password.

## Changing Password During App Use

Users can change their password anytime through:
1. Home screen → Settings/Profile menu (in future update)
2. Or via the ChangePassword endpoint

### Change Password Screen Flow

**Required Fields:**
- Current Password
- New Password
- Confirm New Password

**Validation:**
- Current password must be correct
- New password must meet requirements
- Passwords must match
- New password must differ from current password

## API Authentication Endpoints

### Login
```
POST /api/auth/login
Body: { username, password }
Response: { token, user, message }
```

### Get Current User
```
GET /api/auth/me
Headers: Authorization: Bearer <token>
Response: { id, username, full_name, role, is_default_password }
```

### Change Password
```
POST /api/auth/change-password
Headers: Authorization: Bearer <token>
Body: { currentPassword, newPassword, confirmPassword }
Response: { message: "Password changed successfully" }
```

### Reset Password (Owner Only)
```
POST /api/auth/reset-password/:userId
Headers: Authorization: Bearer <token>
Body: { newPassword }
Response: { message, user, newPassword, note }
```

⚠️ **Note:** Only the owner can reset other users' passwords. The new password is returned and should be shared securely with the user.

## Security Best Practices

### For Users
1. **Change default password immediately** on first login
2. **Use strong passwords** - Don't use simple patterns
3. **Keep password private** - Never share with others
4. **Log out when done** - Especially on shared devices
5. **Change password periodically** - Every 30-60 days recommended
6. **Don't reuse passwords** - Use different passwords for different accounts

### For Owner/Manager
1. **Monitor login attempts** - Check audit logs for unusual activity
2. **Reset compromised passwords** - If a password is leaked
3. **Create unique passwords** for each user account
4. **Maintain records** - Document who has access and when
5. **Require password changes** periodically for compliance

## Installation & Initial Setup

### For Development
1. Database is seeded with default credentials (see above)
2. Login with `receptionist1` / `Reception@123`
3. Change password immediately to your own secure password
4. Share credentials with second receptionist

### For Production Deployment

**Before going live:**

1. **Reset all default passwords:**
   ```bash
   # After starting server, use owner account to reset passwords
   POST /api/auth/reset-password/{receptionist1_id}
   POST /api/auth/reset-password/{receptionist2_id}
   ```

2. **Create new passwords:**
   - Generate strong passwords (min 6 chars, 1 uppercase, 1 number)
   - Examples:
     - `Receptionist@2024Guest`
     - `FacilityMgmt#Guest2024`
     - `SecurePass@2024`

3. **Deliver credentials securely:**
   - Use separate secure channels (email + SMS)
   - Never send both username and password in same message
   - Have users confirm receipt

4. **First login verification:**
   - Ensure each user successfully changes password
   - Document completion date for records

5. **Ongoing security:**
   - Owner maintains audit log of who logged in when
   - Monitor for failed login attempts
   - Reset passwords if staff leaves

## Account Roles & Permissions

### Receptionist Role
- Can record transactions (income/expenses)
- Can edit/delete own entries with reason tracking
- Can view guest ledgers
- Can see daily summary
- Cannot see staff activity or audit trails
- Cannot change other users' passwords

### Owner Role
- Can do everything receptionist can do
- Can view complete audit trails
- Can view staff activity logs
- Can reset other users' passwords
- Can view all financial reports
- Can manage user accounts

## Troubleshooting

### Forgot Password
**Problem:** User forgot their password

**Solution:**
1. Owner logs in with their credentials
2. Owner uses reset password endpoint to set temporary password
3. Owner shares temporary password with user securely
4. User logs in and changes to new password

### Multiple Failed Logins
**Problem:** Too many incorrect password attempts

**Recommendation (Future Update):**
- Implement account lockout after 5 failed attempts
- Implement login timeout (30 minutes)
- Send alerts to owner of suspicious activity

### Lost/Stolen Device
**Problem:** User's phone with saved session is lost

**Solution:**
1. Owner should reset user's password immediately
2. Old token becomes useless (user logged out)
3. User must log in again with new password

## Session Management

### Token Details
- JWT token valid for **24 hours**
- Token stored in device's secure AsyncStorage
- Token auto-expires - user needs to login again
- Logout clears token immediately

### Device Session
- Login information saved on device
- Session persists after app closes/restarts
- Logout clears session completely
- Multiple devices = separate sessions

## Compliance & Audit Trail

Every authentication action is logged:
- ✅ Login timestamp and user
- ✅ Password changes (date, by whom)
- ✅ Password resets (date, by owner)
- ✅ Logout events
- ✅ Failed login attempts (future update)

View audit logs through:
- GET /api/reports/staff-activity (shows login patterns)
- GET /api/reports/audit-trail (shows password changes)

## Password Database Storage

**Important:** Passwords are:
- ✅ **Hashed with bcrypt** (industry-standard)
- ✅ **Never stored in plain text**
- ✅ **Salted** (random added before hashing)
- ✅ **Cannot be reversed** (one-way encryption)
- ✅ **Verified by comparison** (not decryption)

This means:
- Even database admins cannot see user passwords
- Stolen database won't reveal passwords
- Each password hash is unique even for same password

## API Security Features

- ✅ **HTTPS only** (use in production)
- ✅ **JWT token validation** on protected routes
- ✅ **Password strength validation** on change/reset
- ✅ **Audit trail logging** for all auth actions
- ✅ **Role-based access control** (RBAC)
- ✅ **Secure password hashing** (bcrypt)

## Summary

| Aspect | Detail |
|--------|--------|
| Auth Method | Username + Password |
| Users | 2 receptionists + 1 owner |
| Default Passwords | Must be changed on first login |
| Password Requirements | Min 6 chars, 1 uppercase, 1 number |
| Token Expiry | 24 hours |
| Password Hashing | bcrypt with salt |
| Audit Logging | All auth actions logged |
| Role-Based Access | Receptionist vs Owner |

For support or questions about authentication, refer to the implementation or contact your system administrator.
