#!/usr/bin/env bash
# Rebuilds the database from zero, applies every migration in order, and runs
# both test suites. Exits non-zero on the first failure.
#
#   ./src/db/run_tests.sh
#
# Environment:
#   PGHOST / PGPORT / PGUSER   standard libpq vars; PGUSER must be privileged
#   YOURIDER_TEST_DB           database name to (re)create, default yourider_test
#
# The RLS suite runs as an unprivileged role created here. That is not
# incidental: a SUPERUSER or BYPASSRLS role ignores every row-level policy, so
# running those assertions as the migration user would report all-pass while
# testing nothing.

set -euo pipefail

DB="${YOURIDER_TEST_DB:-yourider_test}"
APP_ROLE="yourider_test_app"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

psql_q() { psql -v ON_ERROR_STOP=1 -q "$@"; }

echo "==> recreating database: $DB"
dropdb --if-exists "$DB"
createdb "$DB"

echo "==> applying migrations"
for f in "$HERE"/migrations/*.sql; do
  printf '    %-48s' "$(basename "$f")"
  psql_q -d "$DB" -f "$f" > /tmp/yourider_migrate.out 2>&1 || {
    echo "FAIL"; cat /tmp/yourider_migrate.out; exit 1;
  }
  echo "ok"
done

echo "==> functional suite"
# Run once and reuse the captured output. The suite seeds fixture rows with
# unique slugs/emails, so a second invocation against the same database would
# collide — capture, then assert against what we captured.
FUNC_OUT=$(psql -v ON_ERROR_STOP=1 -d "$DB" -f "$HERE/tests/functional_test.sql" 2>&1) \
  || { echo "$FUNC_OUT"; exit 1; }

echo "$FUNC_OUT" | sed -e 's/^psql:[^ ]* //' -e 's/^NOTICE:  /    /' \
  | grep -Ev '^(DO|CONTEXT)' || true

echo "$FUNC_OUT" | grep -q 'ALL FUNCTIONAL ASSERTIONS PASSED' || {
  echo "    functional suite did not pass"; exit 1; }

echo "==> consent suite"
CONSENT_OUT=$(psql -v ON_ERROR_STOP=1 -d "$DB" -f "$HERE/tests/consent_test.sql" 2>&1) \
  || { echo "$CONSENT_OUT"; exit 1; }

echo "$CONSENT_OUT" | sed -e 's/^psql:[^ ]* //' -e 's/^NOTICE:  /    /' \
  | grep -Ev '^(DO|CONTEXT)' || true

echo "$CONSENT_OUT" | grep -q 'ALL CONSENT ASSERTIONS PASSED' || {
  echo "    consent suite did not pass"; exit 1; }

echo "==> attachments suite"
ATTACH_OUT=$(psql -v ON_ERROR_STOP=1 -d "$DB" -f "$HERE/tests/attachments_test.sql" 2>&1) \
  || { echo "$ATTACH_OUT"; exit 1; }

echo "$ATTACH_OUT" | sed -e 's/^psql:[^ ]* //' -e 's/^NOTICE:  /    /' \
  | grep -Ev '^(DO|CONTEXT)' || true

echo "$ATTACH_OUT" | grep -q 'ALL ATTACHMENT ASSERTIONS PASSED' || {
  echo "    attachments suite did not pass"; exit 1; }

echo "==> pricing suite"
PRICE_OUT=$(psql -v ON_ERROR_STOP=1 -d "$DB" -f "$HERE/tests/pricing_test.sql" 2>&1) \
  || { echo "$PRICE_OUT"; exit 1; }

echo "$PRICE_OUT" | sed -e 's/^psql:[^ ]* //' -e 's/^NOTICE:  /    /' \
  | grep -Ev '^(DO|CONTEXT)' || true

echo "$PRICE_OUT" | grep -q 'ALL PRICING ASSERTIONS PASSED' || {
  echo "    pricing suite did not pass"; exit 1; }

echo "==> creating unprivileged role for RLS suite"
psql_q -d "$DB" <<SQL
DROP ROLE IF EXISTS $APP_ROLE;
CREATE ROLE $APP_ROLE LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT USAGE ON SCHEMA public, app TO $APP_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO $APP_ROLE;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO $APP_ROLE;
SQL

# Resolve fixture ids with the privileged connection. The RLS suite cannot look
# these up itself — with no tenant context set, the policies hide them, which is
# exactly the behaviour under test.
ORG_A=$(psql -At -d "$DB" -c "SELECT id FROM organizations WHERE slug='org-a'")
ORG_B=$(psql -At -d "$DB" -c "SELECT id FROM organizations WHERE slug='org-b'")
USER_A=$(psql -At -d "$DB" -c "SELECT id FROM users WHERE email='a@example.com'")
VIEWER=$(psql -At -d "$DB" -c "SELECT id FROM users WHERE email='v@example.com'")

if [[ -z "$ORG_A" || -z "$ORG_B" ]]; then
  echo "    fixture rows missing; functional suite must run first"; exit 1
fi

echo "==> RLS suite (as $APP_ROLE)"
RLS_OUT=$(PGUSER="$APP_ROLE" PGPASSWORD="" psql -v ON_ERROR_STOP=1 -d "$DB" \
  -v org_a="$ORG_A" -v org_b="$ORG_B" -v user_a="$USER_A" -v viewer="$VIEWER" \
  -f "$HERE/tests/rls_test.sql" 2>&1) || { echo "$RLS_OUT"; exit 1; }

echo "$RLS_OUT" | sed -e 's/^psql:[^ ]* //' -e 's/^NOTICE:  /    /' \
  | grep -Ev '^(DO|CONTEXT)' || true

echo "$RLS_OUT" | grep -q 'ALL RLS ASSERTIONS PASSED' || {
  echo "    RLS suite did not pass"; exit 1; }

echo
echo "==> all suites passed"
