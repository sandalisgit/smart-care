# Smart Care — Complete Setup & Run Guide
## CSG3101 Group 21 | Edith Crown University 2026

---

## Prerequisites — Install These First

| Software | Version | Download |
|---|---|---|
| Java JDK | 17 or higher | https://adoptium.net/temurin/releases |
| Apache Tomcat | 10.1.x | https://tomcat.apache.org/download-10.cgi |
| MySQL Server | 8.0.x | https://dev.mysql.com/downloads/mysql |
| Maven | 3.9.x | https://maven.apache.org/download.cgi |
| VS Code | Latest | https://code.visualstudio.com |

### VS Code Extensions (install these 4)
Open VS Code → Extensions (Ctrl+Shift+X) → search and install:

1. **Extension Pack for Java** — by Microsoft (`vscjava.vscode-java-pack`)
2. **Community Server Connectors** — by Red Hat (Tomcat support)
3. **Maven for Java** — by Microsoft
4. **MySQL Shell for VS Code** — by Oracle (optional, for DB management)

---

## Step 1 — Extract the Project

Unzip `SmartCare_Fixed.zip` to a folder, e.g.:
- Windows: `C:\Projects\SmartCare_Fixed\`
- Mac/Linux: `~/Projects/SmartCare_Fixed/`

---

## Step 2 — Set Up MySQL Database

### 2a. Start MySQL and log in
```bash
mysql -u root -p
```
Enter your MySQL root password.

### 2b. Create the database user
```sql
CREATE USER 'hospital_user'@'localhost' IDENTIFIED BY 'Hospital@2026';
GRANT ALL PRIVILEGES ON hospital_erp.* TO 'hospital_user'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### 2c. Run the SQL scripts IN ORDER
```bash
mysql -u root -p < database/SMARTCARE_COMPLETE_DATABASE.sql
mysql -u root -p hospital_erp < src/main/webapp/WEB-INF/db_additions.sql
mysql -u root -p hospital_erp < src/main/webapp/WEB-INF/auth_fix_patch.sql
```

> **Windows alternative:** Open MySQL Workbench, connect to your server, then run each `.sql` file via File → Open SQL Script → Execute.

### 2d. Verify the database loaded
```sql
mysql -u hospital_user -p hospital_erp
SHOW TABLES;
-- You should see: patients, users, roles, appointments, emr_records, etc.
SELECT COUNT(*) FROM patients;   -- should show 200
SELECT COUNT(*) FROM users;      -- should show 150+
EXIT;
```

---

## Step 3 — Open Project in VS Code

1. Open VS Code
2. **File → Open Folder** → select the `SmartCare_Fixed` folder
3. VS Code will detect it as a Maven project automatically
4. Wait for Java indexing to complete (watch the status bar at the bottom — it shows "Java: Indexing..." then goes away)
5. If prompted "Do you trust this workspace?" → click **Yes, I trust the authors**

---

## Step 4 — Configure Database Connection

Open this file in VS Code:
```
src/main/java/com/smartcare/util/DBConnection.java
```

Check these values match your MySQL setup:
```java
String host   = "localhost";
String port   = "3306";
String dbName = "hospital_erp";
String user   = "hospital_user";
String pass   = "Hospital@2026";
```

Change them if your MySQL uses a different port or password.

---

## Step 5 — Build the Project

Open the VS Code Terminal (**Ctrl+`** or **View → Terminal**) and run:

```bash
mvn clean package -DskipTests
```

This will:
- Download all dependencies (first time takes 2–5 minutes)
- Compile all Java files
- Create `target/smart-care.war`

You should see:
```
BUILD SUCCESS
```

If you see errors, check:
- Java 17+ is installed: `java -version`
- Maven is installed: `mvn -version`
- Internet connection (first build downloads dependencies)

---

## Step 6 — Deploy to Tomcat in VS Code

### 6a. Add Tomcat server
1. In VS Code, press **Ctrl+Shift+P** → type "Servers" → select **Create New Server**
2. Choose **Apache Tomcat** → select your Tomcat 10.1 installation folder
3. The server appears in the **Servers** panel (bottom left)

### 6b. Deploy the WAR
1. In VS Code Explorer, right-click on `target/smart-care.war`
2. Select **Run on Server** (or drag the WAR into the Servers panel)
3. Select your Tomcat 10.1 server

### 6c. Start the server
1. In the Servers panel, right-click your Tomcat → **Start**
2. Watch the terminal output for:
   ```
   INFO: Server startup in [XXXX] milliseconds
   ```

---

## Step 7 — Open the Application

Open your browser and go to:

```
http://localhost:8080/smart-care/
```

---

## Login Credentials

### Staff Login (index.html)
| Role | Username | Password | MFA Required |
|---|---|---|---|
| System Admin | `admin` | `Admin@2026!` | Yes (TOTP app) |
| Doctor | `dr.silva` | `Doctor@2026!` | Yes (TOTP app) |
| Pharmacist | `pharmacist` | `Pharm@2026!` | No |
| Billing Clerk | `billing` | `Billing@2026!` | Yes (TOTP app) |
| Receptionist | `reception` | `Recept@2026!` | No |

### Patient Login (pages/auth/patient-login.html)
Patient login uses **Patient ID + Full Name** — no password.

| Patient ID | Full Name |
|---|---|
| PAT000001 | Saman Silva |
| PAT000002 | Dilini Fernando |
| PAT000003 | Kasun Perera |
| PAT000004 | Nimali Rajapaksa |
| PAT000005 | Tharindu Bandara |

### MFA Setup (First Login for Admin/Doctor/Billing)
1. Log in with username + password
2. You are redirected to the MFA setup page
3. Install **Google Authenticator** or **Microsoft Authenticator** on your phone
4. Scan the QR code shown on screen
5. Enter the 6-digit code from your app
6. MFA is now enabled — subsequent logins just need the code

---

## Sidebar Navigation

The sidebar has **two columns** (matching the wireframe design):

- **Left column** (dark blue `#2C4A6E`) — 9 main modules
- **Right column** (slightly darker `#16253A`) — sub-pages, appears when a module is selected

| Module | Sub-pages |
|---|---|
| Patient Management | Patients · Register Patient · Search · Reports |
| Appointments | Book Appointment · Search/Filter · Today's Schedule · Reports |
| EMR | Patient Records · New Entry · Documents · Reports |
| Pharmacy | Inventory · Dispense · Orders · Reports |
| Billing | Invoices · Payments · Insurance Claims · Reports |
| Bed & Ward | Ward Overview · Admit · Transfers · Discharge · Reports |
| Staff & HR | Staff Profiles · Create Profile · Scheduling · Attendance · Leave · Reports |
| Security & Audit | Audit Log · User Mgmt · RBAC Roles · Anomaly Alerts · HIPAA Report |

---

## Troubleshooting

### Port 8080 already in use
Edit Tomcat's `conf/server.xml`, change:
```xml
<Connector port="8080" ...
```
to:
```xml
<Connector port="8090" ...
```
Then browse to `http://localhost:8090/smart-care/`

### Cannot connect to database
- Check MySQL is running: `mysqladmin -u root -p status`
- Verify DBConnection.java credentials match your MySQL setup
- Make sure `hospital_user` exists: `SELECT user FROM mysql.user;`

### 404 error on all pages
- The WAR must deploy as context path `/smart-care`
- Check Tomcat Manager at `http://localhost:8080/manager/html`
- Look for `smart-care` in the list — it should say "running"

### MFA code always wrong
- TOTP is time-based — your PC and phone clocks must be in sync
- On phone: Settings → Date & Time → Set Automatically → ON
- Try waiting for the code to refresh (every 30 seconds)
- In demo mode (no backend): the frontend accepts any 6-digit code

### Java compilation errors
- Check `java -version` shows 17 or higher
- In VS Code: **Ctrl+Shift+P** → "Java: Configure Java Runtime" → set JDK 17

### Rebuild after changes
```bash
mvn clean package -DskipTests
```
Then in VS Code Servers panel: right-click Tomcat → **Restart**

---

## Project Structure

```
SmartCare_Fixed/
├── database/
│   └── SMARTCARE_COMPLETE_DATABASE.sql    ← Main DB schema + seed data
├── src/
│   └── main/
│       ├── java/com/smartcare/
│       │   ├── filter/AuthFilter.java     ← JWT session validation
│       │   ├── security/AuthService.java  ← Login, MFA, patient auth
│       │   ├── servlet/AuthServlet.java   ← /api/auth/* endpoints
│       │   ├── dao/                       ← Database access objects
│       │   ├── ai/                        ← AI models (no-show, anomaly)
│       │   └── util/DBConnection.java     ← MySQL connection pool
│       └── webapp/
│           ├── index.html                 ← Staff login page
│           ├── css/app.css                ← Master design system
│           ├── js/
│           │   ├── app.js                 ← API client, Auth, Toast
│           │   └── sidebar.js             ← Two-column sidebar renderer
│           ├── pages/
│           │   ├── auth/
│           │   │   ├── mfa.html           ← TOTP setup + verify
│           │   │   └── patient-login.html ← Patient ID + name login
│           │   ├── admin/dashboard.html   ← Main dashboard
│           │   ├── patients/list.html     ← Patient management
│           │   ├── appointments/book.html ← Appointment booking
│           │   ├── emr/records.html       ← Electronic medical records
│           │   ├── pharmacy/dashboard.html← Pharmacy inventory
│           │   ├── billing/dashboard.html ← Billing & invoices
│           │   ├── beds/ward.html         ← Bed & ward management
│           │   ├── staff/employees.html   ← Staff & HR
│           │   ├── staff/doctor-dashboard.html ← Doctor portal
│           │   ├── security/dashboard.html← Security & audit
│           │   └── patients/patient-portal.html ← Patient portal
│           └── WEB-INF/
│               ├── web.xml                ← Servlet config
│               ├── db_additions.sql       ← MFA + AI tables
│               └── auth_fix_patch.sql     ← Demo accounts + patient_sessions
├── pom.xml                                ← Maven dependencies
└── HOW_TO_RUN.md                          ← This file
```

---

## Colors (from XML wireframe)

| Element | Color Code |
|---|---|
| Topbar background | `#1E3A5F` |
| Main sidebar | `#2C4A6E` |
| Active sidebar item | `#3A6186` |
| Sub-sidebar | `#16253A` |
| "Smart" brand text | `#18AEBA` (teal) |
| "Care" brand text | `#FC9E09` (orange) |
| Accent / links | `#18AEBA` |
