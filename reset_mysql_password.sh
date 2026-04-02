#!/bin/bash
# MySQL 8.0 Complete Reinstall Script
# This wipes MySQL and reinstalls it fresh with no root password.
# Run with: bash reset_mysql_password.sh

echo "==> Step 1: Stopping MySQL service..."
brew services stop mysql@8.0
sleep 2

echo "==> Step 2: Uninstalling MySQL..."
brew uninstall mysql@8.0
sleep 2

echo "==> Step 3: Removing leftover data files..."
BREW_PREFIX=$(brew --prefix)
rm -rf "$BREW_PREFIX/var/mysql"
sleep 1

echo "==> Step 4: Reinstalling MySQL 8.0..."
brew install mysql@8.0
sleep 2

echo "==> Step 5: Starting MySQL..."
brew services start mysql@8.0
sleep 4

echo "==> Step 6: Testing connection (should print OK)..."
"$BREW_PREFIX/opt/mysql@8.0/bin/mysql" -u root -e "SELECT 'OK';"

echo ""
echo "If you see OK above, MySQL is ready with no password."
echo "You can now run the database setup commands."
