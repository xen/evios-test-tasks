from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlmodel import func, select

from app.api.deps import SessionDep, require_metrics
from app.models import Item, User

router = APIRouter(prefix="/metrics", tags=["metrics"])


class MetricsPublic(BaseModel):
    users: int
    items: int


@router.get("/", response_model=MetricsPublic, dependencies=[Depends(require_metrics)])
def read_metrics(session: SessionDep) -> MetricsPublic:
    return MetricsPublic(
        users=session.exec(select(func.count()).select_from(User)).one(),
        items=session.exec(select(func.count()).select_from(Item)).one(),
    )
