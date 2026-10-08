"""drop legacy column"""
from alembic import op

revision = "001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_table("customers")
    op.drop_column("orders", "legacy_id")
    op.alter_column("users", "email", nullable=False)
    op.create_index("idx_users_email", "users", ["email"])


def downgrade() -> None:
    pass
