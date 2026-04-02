# Smart Care — Setup & Run Guide (macOS)
## CSG3101 Group 21 | Edith Crown University 2026

> **On Windows or Linux?** See [HOW_TO_RUN.md](HOW_TO_RUN.md).

---

## Prerequisites

You need **Homebrew**. If you don't have it:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

---

## Full Setup — Copy & Paste

Run these commands in Terminal, one section at a time:

### 1. Install all required tools
```bash
brew install --cask temurin@17
brew install maven
brew install mysql@8.0
brew install tomcat@10
```

### 2. Set Java 17 as default (permanent)
```bash
echo 'export JAVA_HOME=$(/usr/libexec/java_home -v 17)' >> ~/.zshrc
source ~/.zshrc
java -version   # should show 17.x.x
```

### 3. Start MySQL
```bash
brew services start mysql@8.0
```

### 4. Clone the repo
```bash
git clone https://github.com/sandalisgit/smart-care.git
cd smart-care
```

### 5. Set up the database (run IN ORDER)

> Each command will prompt: `Enter password:` — type your MySQL root password and press Enter.
> If MySQL was freshly installed and you never set a password, just press Enter (blank).

```bash
/opt/homebrew/opt/mysql@8.0/bin/mysql -u root -p < database/SMARTCARE_COMPLETE_DATABASE.sql

/opt/homebrew/opt/mysql@8.0/bin/mysql -u root -p -e \
  "CREATE USER IF NOT EXISTS 'hospital_user'@'localhost' IDENTIFIED BY 'Hospital@2026'; \
   GRANT ALL PRIVILEGES ON hospital_erp.* TO 'hospital_user'@'localhost'; \
   FLUSH PRIVILEGES;"

/opt/homebrew/opt/mysql@8.0/bin/mysql -u root -p hospital_erp < src/main/webapp/WEB-INF/db_additions.sql
/opt/homebrew/opt/mysql@8.0/bin/mysql -u root -p hospital_erp < src/main/webapp/WEB-INF/auth_fix_patch.sql
```

### 6. Build
```bash
mvn clean package -DskipTests
```
First run takes 2–5 minutes. You should see `BUILD SUCCESS`.

### 7. Deploy and start Tomcat
```bash
cp target/smart-care.war /opt/homebrew/opt/tomcat@10/libexec/webapps/
brew services start tomcat@10
```

### 8. Open the app
Wait ~10 seconds for deployment, then open:
```
http://localhost:8080/smart-care/
```

---

## Login Credentials

### Staff Login
| Role | Username | Password | MFA Required |
|---|---|---|---|
| System Admin | `admin` | `Admin@2026!` | Yes (TOTP app) |
| Doctor | `dr.silva` | `Doctor@2026!` | Yes (TOTP app) |
| Pharmacist | `pharmacist` | `Pharm@2026!` | No |
| Billing Clerk | `billing` | `Billing@2026!` | Yes (TOTP app) |
| Receptionist | `reception` | `Recept@2026!` | No |

### Patient Login (`/pages/auth/patient-login.html`)
Patient login uses **Patient ID + Full Name** — no password.

| Patient ID | Full Name |
|---|---|
| PAT000001 | Saman Silva |
| PAT000002 | Dilini Fernando |
| PAT000003 | Kasun Perera |
| PAT000004 | Nimali Rajapaksa |
| PAT000005 | Tharindu Bandara |

### MFA First-Time Setup (Admin / Doctor / Billing)
1. Log in with username + password
2. You are redirected to the MFA setup page
3. Install **Google Authenticator** or **Microsoft Authenticator** on your phone
4. Scan the QR code shown on screen
5. Enter the 6-digit code from your app

---

## Day-to-Day Commands

### Start everything (after a reboot)
```bash
brew services start mysql@8.0
brew services start tomcat@10
```

### Stop everything
```bash
brew services stop tomcat@10
brew services stop mysql@8.0
```

### Rebuild and redeploy after code changes
```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
mvn clean package -DskipTests
brew services stop tomcat@10
rm -rf /opt/homebrew/opt/tomcat@10/libexec/webapps/smart-care*
cp target/smart-care.war /opt/homebrew/opt/tomcat@10/libexec/webapps/
brew services start tomcat@10
```

### View Tomcat logs (for debugging)
```bash
tail -f /opt/homebrew/Cellar/tomcat@10/*/libexec/logs/localhost.$(date +%Y-%m-%d).log
```

### Connect to MySQL
```bash
/opt/homebrew/opt/mysql@8.0/bin/mysql -u root -p hospital_erp
```

---

## Troubleshooting

### `java -version` shows wrong version after install
```bash
source ~/.zshrc
java -version   # should now show 17.x.x
```
If still wrong, make sure `export JAVA_HOME=$(/usr/libexec/java_home -v 17)` is in your `~/.zshrc`.

### Port 8080 already in use
```bash
lsof -i :8080          # find what's using the port
kill -9 <PID>          # kill it
brew services restart tomcat@10
```
Or change Tomcat's port in `/opt/homebrew/etc/tomcat@10/server.xml`:
```xml
<Connector port="8090" ...
```
Then browse to `http://localhost:8090/smart-care/`

### Cannot connect to database (500 error on login)
```bash
brew services list | grep mysql     # should show "started"
brew services start mysql@8.0       # start it if stopped
```

### Access denied for root (using password: NO)
Your MySQL root account has a password. Add `-p` to every `mysql` command — it will prompt you to enter it:
```bash
/opt/homebrew/opt/mysql@8.0/bin/mysql -u root -p < database/SMARTCARE_COMPLETE_DATABASE.sql
```
If you've forgotten the root password, reset it:
```bash
brew services stop mysql@8.0
/opt/homebrew/opt/mysql@8.0/bin/mysqld_safe --skip-grant-tables &
sleep 3
/opt/homebrew/opt/mysql@8.0/bin/mysql -u root
```
Then inside MySQL:
```sql
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY 'YourNewPassword';
EXIT;
```
Then: `brew services restart mysql@8.0`

### MFA code always rejected
- Your Mac and phone clocks must be in sync
- Phone: Settings → General → Date & Time → Set Automatically → ON
- Codes rotate every 30 seconds — wait for a fresh code and try again

### BUILD FAILURE — wrong Java version
```bash
/usr/libexec/java_home -V                        # lists all installed JVMs
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
mvn clean package -DskipTests                    # retry
```
