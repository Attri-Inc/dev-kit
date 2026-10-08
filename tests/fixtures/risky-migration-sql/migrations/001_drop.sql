-- Risky: drops a populated production table outright
DROP TABLE customers;
DROP COLUMN orders.legacy_id;
TRUNCATE TABLE audit_log;
DELETE FROM sessions;
ALTER TABLE users ADD COLUMN email_verified BOOLEAN NOT NULL;
CREATE INDEX idx_users_email ON users(email);
