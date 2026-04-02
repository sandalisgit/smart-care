# Smart Care — Auth Fix & MFA Update
## CSG3101 Group 21 | Edith Crown University 2026

---

## Files Changed

| File | Change |
|------|--------|
| `src/main/webapp/index.html` | Staff-only login; demo credentials panel with "Use" buttons; routes to MFA on success |
| `src/main/webapp/pages/auth/patient-login.html` | Patient ID + Full Name only; no password; 5 demo accounts; staff cannot use this page |
| `src/main/webapp/pages/auth/mfa.html` | Full two-tab TOTP flow: First-time Setup (QR + secret key + app instructions) and Enter Code (verify) |
| `src/main/webapp/js/app.js` | Added `requireStaff()`, `requirePatient()` guards; fixed logout routing; `requiresMfaSetup` handling |
| `src/main/java/.../security/AuthService.java` | Added `patientLogin()`, `setupAndVerifyMfa()`, `requiresMfaSetup` flag, `PatientLoginResult` DTO |
| `src/main/java/.../servlet/AuthServlet.java` | Added `/patient-login`, `/mfa-setup-verify`, `/mfa-enroll` endpoints |
| `src/main/webapp/WEB-INF/auth_fix_patch.sql` | `patient_sessions` table; demo staff + patient accounts; Receptionist role |

---

## What Was Fixed

### 1. Patient Login (patient-login.html)
**Before:** Used the same username/password form as staff. Admin credentials worked on patient portal.

**After:**
- Accepts **Patient ID** (PAT000001 format) + **registered full name** only — no password
- Backend validates the PAT prefix and rejects anything else
- Name match is case-insensitive
- 5 demo patients with "Use" buttons to auto-fill the form

**Demo Patients:**
| Patient ID | Full Name |
|---|---|
| PAT000001 | Saman Silva |
| PAT000002 | Dilini Fernando |
| PAT000003 | Kasun Perera |
| PAT000004 | Nimali Rajapaksa |
| PAT000005 | Tharindu Bandara |

---

### 2. Staff Login (index.html)
- Demo credentials panel for all 5 roles with "Use" buttons
- Routes to `mfa.html` for MFA-required roles (both setup and verify)
- `requiresMfa` → go to verify tab; `requiresMfaSetup` → go to setup tab

**Demo Staff:**
| Role | Username | Password |
|---|---|---|
| System Admin | admin | Admin@2026! |
| Doctor | dr.silva | Doctor@2026! |
| Pharmacist | pharmacist | Pharm@2026! |
| Billing Clerk | billing | Billing@2026! |
| Receptionist | reception | Recept@2026! |

---

### 3. MFA Page (mfa.html)
**Before:** Just a 6-digit box. No real setup flow. "Resend code" did nothing.

**After — Two-tab TOTP flow:**

**Tab 1: First-time Setup**
1. Install authenticator app (Google Authenticator / Microsoft / Authy)
2. Scan QR code (or enter secret key manually — `JBSWY3DPEHPKNPXBP` in demo)
3. Enter the 6-digit code to verify and enable MFA
4. Live 30-second countdown with color-coded progress bar (green → orange → red)

**Tab 2: Enter Code (subsequent logins)**
1. 6-digit entry with auto-advance between boxes
2. Auto-submits on last digit
3. 30-second countdown
4. "Re-scan QR code" link goes back to Setup tab
5. Clear error messages

**Auto-routing:** If a `sc_mfa_token` is in sessionStorage, goes directly to Enter Code tab.

---

## How to Deploy

```bash
# 1. Run the SQL patch
mysql -u root -p hospital_erp < src/main/webapp/WEB-INF/auth_fix_patch.sql

# 2. Build
mvn clean package

# 3. Deploy
cp target/smart-care.war /path/to/tomcat/webapps/
```

---

## MFA-Required Roles (FR-72)
- System Admin
- Hospital Admin
- Doctor
- Billing Clerk

Other roles (Pharmacist, Nurse, Receptionist, HR Manager) bypass MFA but can enroll voluntarily.
