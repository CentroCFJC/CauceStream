"""devices.mac_address

Revision ID: 0009
Revises: 0008
Create Date: 2026-10-30

Adds the MAC address used by the server-side Wake-on-LAN power-on
(app/power/). Nullable: devices that are never WoL targets (or whose MAC
is not known yet) simply stay null.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0009"
down_revision: Union[str, None] = "0008"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("devices") as batch_op:
        batch_op.add_column(sa.Column("mac_address", sa.String(length=17), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("devices") as batch_op:
        batch_op.drop_column("mac_address")
