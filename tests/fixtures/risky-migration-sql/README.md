# Fixture: risky-migration-sql

**Expected to be caught by:** `migration-safety` action.

Plants every risky pattern: `DROP TABLE`, `DROP COLUMN`, `TRUNCATE`, `DELETE FROM ... ;` (no WHERE), `ALTER ... NOT NULL` (no DEFAULT), `CREATE INDEX` (no CONCURRENTLY).
