# Smart Care — Complete Setup & Run Guide
## CSG3101 Group 21 | Edith Crown University 2026

---

## Mac (Homebrew) — Quickest Setup

If you're on a Mac with [Homebrew](https://brew.sh) installed, run these commands in order:

```bash
# 1. Install all required tools
brew install --cask temurin@17
brew install maven
brew install mysql@8.0
brew install tomcat@10

# 2. Set Java 17 as default (add to ~/.zshrc to make permanent)
export JAVA_HOME=$(/usr/libexec/java_home -v 17)

# 3. Start MySQL
brew services start mysql@8.0

# 4. Clone the repo
git clone https://github.com/sandalisgit/smart-care.git
cd smart-care

# 5. Load the database (run IN ORDER)
/opt/homebrew/opt/mysql@8.0/bin/mysql -u root < database/SMARTCARE_COMPLETE_DATABASE.sql
/opt/homebrew/opt/mysql@8.0/bin/mysql -u root -e "CREATE USER IF NOT EXISTS 'hospital_user'@'localhost' IDENTIFIED BY 'Hospital@2026'; GRANT ALL PRIVILEGES ON hospital_erp.* TO 'hospital_user'@'localhost'; FLUSH PRIVILEGES;"
/opt/homebrew/opt/mysql@8.0/bin/mysql -u root hospital_erp < src/main/webapp/WEB-INF/db_additions.sql
/opt/homebrew/opt/mysql@8.0/bin/mysql -u root hospital_erp < src/main/webapp/WEB-INF/auth_fix_patch.sql

# 6. Build
mvn clean package -DskipTests

# 7. Deploy and start Tomcat
cp target/smart-care.war /opt/homebrew/opt/tomcat@10/libexec/webapps/
brew services start tomcat@10
```

Then open: **http://localhost:8080/smart-care/**

---

## Windows / Linux — Manual Setup

### Prerequisites — Install These First

| Software | Version | Download |
|---|---|---|
| Java JDK | 17 | https://adoptium.net/temurin/releases |
| Apache Tomcat | 10.1.x | https://tomcat.apache.org/download-10.cgi |
| MySQL Server | 8.0.x | https://dev.mysql.com/downloads/mysql |
| Maven | 3.9.x | https://maven.apache.org/download.cgi |
| Git | Latest | https://git-scm.com |

> **Important:** Use **Java 17** specifically. Java 21+ may work but is untested.

### Step 1 — Clone the Repository

```bash
git clone https://github.com/sandalisgit/smart-care.git
cd smart-care
```

---

### Step 2 — Set Up MySQL Database

#### 2a. Start MySQL and create the database user
```bash
mysql -u root -p
```
```sql
CREATE USER 'hospital_user'@'localhost' IDENTIFIED BY 'Hospital@2026';
GRANT ALL PRIVILEGES ON hospital_erp.* TO 'hospital_user'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

#### 2b. Run the SQL scripts IN ORDER
```bash
mysql -u root -p < database/SMARTCARE_COMPLETE_DATABASE.sql
mysql -u root -p hospital_erp < src/main/webapp/WEB-INF/db_additions.sql
mysql -u root -p hospital_erp < src/main/webapp/WEB-INF/auth_fix_patch.sql
```

> **Windows alternative:** Open MySQL Workbench → File → Open SQL Script → run each file.

#### 2c. Verify the database loaded
```sql
mysql -u hospital_user -p hospital_erp
SHOW TABLES;          -- should show 55+ tables
SELECT COUNT(*) FROM patients;   -- should show 200
SELECT COUNT(*) FROM users;      -- should show 150+
EXIT;
```

---

### Step 3 — Configure JAVA_HOME

Make sure `JAVA_HOME` points to Java 17:

```bash
# Mac/Linux — add to ~/.zshrc or ~/.bashrc
export JAVA_HOME=$(/usr/libexec/java_home -v 17)   # Mac only
# or
export JAVA_HOME=/path/to/jdk-17

# Windows — set System Environment Variable
JAVA_HOME = C:\Program Files\Eclipse Adoptium\jdk-17.x.x
```

Verify: `java -version` should show `17.x.x`

---

### Step 4 — Build the Project

```bash
mvn clean package -DskipTests
```

You should see `BUILD SUCCESS` and a file `target/smart-care.war` created.

---

### Step 5 — Deploy to Tomcat

Copy the WAR into Tomcat's webapps folder:

```bash
# Mac (Homebrew)
cp target/smart-care.war /opt/homebrew/opt/tomcat@10/libexec/webapps/

# Linux / manual install — replace with your Tomcat path
cp target/smart-care.war /opt/tomcat/webapps/

# Windows — replace with your Tomcat path
copy target\smart-care.war C:\tomcat\webapps\
```

Then start Tomcat:

```bash
# Mac (Homebrew)
brew services start tomcat@10

# Linux / manual
$CATALINA_HOME/bin/startup.sh

# Windows
%CATALINA_HOME%\bin\startup.bat
```

Wait for the log line: `INFO: Server startup in [XXXX] milliseconds`

---

### Step 6 — Open the Application

```
http://localhost:8080/smart-care/
```

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
