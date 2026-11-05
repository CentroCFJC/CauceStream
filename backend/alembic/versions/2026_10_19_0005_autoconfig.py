"""autoconfig: state table + pending devices

Revision ID: 0005
Revises: 0004
Create Date: 2026-10-19

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0005"
down_revision: Union[str, None] = "0004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Autoconfig mode flag (single row) and pending devices."""
    op.create_table(
        "autoconfig_state",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.create_table(
        "autoconfig_pending_devices",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("device_uid", sa.String(length=100), nullable=False),
        sa.Column("ip_address", sa.String(length=45), nullable=False),
        sa.Column("device_state", sa.String(length=20), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=True),
        sa.Column(
            "last_seen", sa.DateTime(timezone=True), nullable=False, index=True
        ),
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
        "uq_autoconfig_pending_device_uid",
        "autoconfig_pending_devices",
        ["device_uid"],
    )


def downgrade() -> None:
    """Drop autoconfig tables."""
    op.drop_table("autoconfig_pending_devices")
    op.drop_table("autoconfig_state")
