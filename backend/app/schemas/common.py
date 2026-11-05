"""Shared schema types."""

from typing import Annotated

from pydantic import Field

# Cauce passwords are 4-digit numeric PINs: quick access is part of the
# room's operating philosophy. The format is validated consistently for
# login, creation and update.
Pin = Annotated[str, Field(pattern=r"^\d{4}$", description="PIN numerico de 4 digitos")]
