#!/bin/bash
# uninstall-kjol.sh — Completely uninstall Kjol and its privileged helper daemon.

set -e

HELPER_LABEL="com.lappier.kjol.helper"
CAFFEINATE_LABEL="com.lappier.kjol.caffeinate"
DST_BIN="/Library/PrivilegedHelperTools/$HELPER_LABEL"
DST_PLIST="/Library/LaunchDaemons/$HELPER_LABEL.plist"
CAFFEINATE_PLIST="/Library/LaunchDaemons/$CAFFEINATE_LABEL.plist"
APP_DIR="/Applications/Kjol.app"
STATE_DIR="/var/db/kjol"
LOG_OUT="/var/log/kjol-helper.out.log"
LOG_ERR="/var/log/kjol-helper.err.log"

if [ "$(id -u)" -ne 0 ]; then
    echo "→ Requesting administrator privileges to uninstall Kjol..."
    sudo "$0" "$@"
    exit 0
fi

echo "=== Uninstalling Kjol ==="

# 1. Terminate running Kjol app instances
echo "→ Closing Kjol application..."
pkill -x "Kjol" 2>/dev/null || true

# 2. Boot out and disable the LaunchDaemons
echo "→ Stopping and unregistering privileged helper daemon and legacy daemons..."
launchctl bootout "system/$HELPER_LABEL" 2>/dev/null || true
launchctl disable "system/$HELPER_LABEL" 2>/dev/null || true
launchctl bootout "system/$CAFFEINATE_LABEL" 2>/dev/null || true
launchctl disable "system/$CAFFEINATE_LABEL" 2>/dev/null || true

# 3. Remove privileged helper files
echo "→ Removing helper binary and launchd plists..."
rm -f "$DST_BIN"
rm -f "$DST_PLIST"
rm -f "$CAFFEINATE_PLIST"

# 4. Remove state directory and helper logs
echo "→ Cleaning up persistent state and logs..."
rm -rf "$STATE_DIR"
rm -f "$LOG_OUT" "$LOG_ERR"

# 5. Remove Application bundle
if [ -d "$APP_DIR" ]; then
    echo "→ Removing $APP_DIR..."
    rm -rf "$APP_DIR"
fi

# 6. Reset power management disablesleep setting if left modified
pmset -a disablesleep 0 2>/dev/null || true

echo "=== Kjol has been completely uninstalled ==="
