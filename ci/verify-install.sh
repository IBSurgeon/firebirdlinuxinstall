#!/usr/bin/env bash
#
# CI smoke test for a Firebird installation made by the fb_*.sh scripts.
# Usage: ci/verify-install.sh <systemd-service-name>
# Expects: Firebird installed to /opt/firebird, SYSDBA password "masterkey".

set -euo pipefail

SERVICE="${1:?Usage: verify-install.sh <systemd-service-name>}"
FB_ROOT="/opt/firebird"
ISQL="$FB_ROOT/bin/isql"
# The install scripts chown examples/empbuild to the firebird user,
# so it is the one location the server is guaranteed to be able to
# write to for a smoke-test database.
TEST_DB="$FB_ROOT/examples/empbuild/ci_smoke_test.fdb"

fail() {
	echo "::error::$1"
	exit 1
}

echo "### systemd service: $SERVICE"
if ! systemctl is-active "$SERVICE"; then
	journalctl -u "$SERVICE" --no-pager -n 100 || true
	fail "Service $SERVICE is not active"
fi

echo "### port 3050 is listening"
if (exec 3<>/dev/tcp/127.0.0.1/3050) 2>/dev/null; then
	echo "OK: port 3050 accepts connections"
else
	fail "Port 3050 is not accepting connections on 127.0.0.1"
fi

echo "### isql client version"
"$ISQL" -z

echo "### TCP smoke test: create, select, drop"
rm -f "$TEST_DB"
"$ISQL" -user SYSDBA -password masterkey <<SQL || fail "isql smoke test failed"
create database 'localhost:$TEST_DB';
select 1 as smoke_test_ok from rdb\$database;
commit;
drop database;
quit;
SQL

# Informational only: the employee example is a good extra check but its
# presence/alias differ between Firebird versions and config archives.
echo "### employee.fdb (informational)"
if [ -f "$FB_ROOT/examples/empbuild/employee.fdb" ] && grep -q '^employee' "$FB_ROOT/databases.conf" 2>/dev/null; then
	echo "select 'employee alias ok' from rdb\$database;" |
		"$ISQL" -user SYSDBA -password masterkey localhost:employee ||
		echo "WARNING: could not connect through the employee alias (non-fatal)"
else
	echo "employee.fdb or its alias not found (non-fatal)"
fi

echo "PASS: Firebird is installed and working"
