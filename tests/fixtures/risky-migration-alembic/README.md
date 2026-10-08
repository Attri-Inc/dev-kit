# Fixture: risky-migration-alembic

**Expected to be caught by:** `migration-safety` action (Alembic Python flavor).

Plants `op.drop_table`, `op.drop_column`, `op.alter_column(..., nullable=False)`, and `op.create_index` without `postgresql_concurrently=True`.
