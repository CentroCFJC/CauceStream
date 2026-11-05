"""device_media_assignments.revision

Revision ID: 0008
Revises: 0007
Create Date: 2026-10-19

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0008"
down_revision: Union[str, None] = "0007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Monotonic per-device revision of the desired assignment."""
    op.add_column(
        "device_media_assignments",
        sa.Column("revision", sa.Integer(), nullable=False, server_default="1"),
    )


def downgrade() -> None:
    """Drop the revision column."""
    op.drop_column("device_media_assignments", "revision")
