"""devices.display_state -> devices.device_state

Revision ID: 0004
Revises: 0003
Create Date: 2026-10-19

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0004"
down_revision: Union[str, None] = "0003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Rename display_state to device_state.

    Pure rename: stored values are free text, so rows holding the retired
    `awake`/`asleep` values stay as-is until each device reports again
    under the new `active`/`idle` vocabulary.
    """
    with op.batch_alter_table("devices") as batch_op:
        batch_op.alter_column(
            "display_state", new_column_name="device_state", type_=sa.String(length=20)
        )


def downgrade() -> None:
    """Rename device_state back to display_state."""
    with op.batch_alter_table("devices") as batch_op:
        batch_op.alter_column(
            "device_state", new_column_name="display_state", type_=sa.String(length=20)
        )
