"""devices.payload

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-16

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0003"
down_revision: Union[str, None] = "0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add the heartbeat payload column (additive, nullable)."""
    op.add_column("devices", sa.Column("payload", sa.JSON(), nullable=True))


def downgrade() -> None:
    """Drop the heartbeat payload column."""
    op.drop_column("devices", "payload")
