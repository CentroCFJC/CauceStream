"""devices.current_media + device_media_assignments

Revision ID: 0007
Revises: 0006
Create Date: 2026-10-19

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0007"
down_revision: Union[str, None] = "0006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Rename current_application to current_media.

    Old values were application names, not media ids, and must never be
    interpreted as a played media: every previously reported value is
    reset to 'unknown' so the first heartbeat under the new contract
    re-establishes the real state.
    """
    with op.batch_alter_table("devices") as batch_op:
        batch_op.alter_column(
            "current_application",
            new_column_name="current_media",
            type_=sa.String(length=100),
        )
    op.execute("UPDATE devices SET current_media = 'unknown' WHERE current_media IS NOT NULL")

    op.create_table(
        "device_media_assignments",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "device_id",
            sa.Integer(),
            sa.ForeignKey("devices.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "media_id",
            sa.Integer(),
            sa.ForeignKey("media.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("sync_status", sa.String(length=20), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_unique_constraint(
        "uq_device_media_assignments_device_id",
        "device_media_assignments",
        ["device_id"],
    )


def downgrade() -> None:
    """Drop assignments; restore the old column name.

    Current values are media ids/'unknown', not application names, so
    they are nulled out rather than faked.
    """
    op.drop_table("device_media_assignments")
    with op.batch_alter_table("devices") as batch_op:
        batch_op.alter_column(
            "current_media",
            new_column_name="current_application",
            type_=sa.String(length=100),
        )
    op.execute("UPDATE devices SET current_application = NULL")
