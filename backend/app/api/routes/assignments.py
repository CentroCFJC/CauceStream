"""Device-media assignment listing endpoint."""

from fastapi import APIRouter, Depends

from app.api.deps import get_assignment_service, require_permission
from app.models.user import User
from app.schemas.assignment import AssignmentRead
from app.services.assignment_service import AssignmentService

router = APIRouter(prefix="/assignments", tags=["assignments"])


@router.get(
    "",
    response_model=list[AssignmentRead],
    summary="Current media assignments and their sync states",
)
async def list_assignments(
    actor: User = Depends(require_permission("content.view")),
    service: AssignmentService = Depends(get_assignment_service),
):
    """All vigente assignments (one per device) in a single query, with
    the media the administration assigned and whether each device
    reports playing it (`synchronized` | `pending`)."""
    return await service.list_all()
