"""Replace superuser flag with named roles, preserving existing administrators."""
from alembic import op
import sqlalchemy as sa

revision = "7b20a1d9f032"
down_revision = "fe56fa70289e"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("user", sa.Column("role", sa.String(16), nullable=False, server_default="member"))
    op.execute("UPDATE \"user\" SET role = 'admin' WHERE is_superuser = true")
    op.create_check_constraint("user_role_check", "user", "role IN ('admin', 'manager', 'member')")
    op.drop_column("user", "is_superuser")
    op.alter_column("user", "role", server_default=None)


def downgrade():
    op.add_column("user", sa.Column("is_superuser", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.execute("UPDATE \"user\" SET is_superuser = (role = 'admin')")
    op.drop_constraint("user_role_check", "user", type_="check")
    op.drop_column("user", "role")
    op.alter_column("user", "is_superuser", server_default=None)
