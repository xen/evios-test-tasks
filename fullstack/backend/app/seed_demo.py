"""Create local demo accounts without changing existing accounts."""

import os

from sqlmodel import Session

from app import crud
from app.core.config import settings
from app.core.db import engine, init_db
from app.models import UserCreate
from app.permissions import Role


def main() -> None:
    password = os.environ["DEMO_PASSWORD"]
    with Session(engine) as session:
        init_db(session)
        for role in (Role.MANAGER, Role.MEMBER):
            email = f"{role.value}@example.com"
            existing = crud.get_user_by_email(session=session, email=email)
            if existing:
                if existing.role != role or not existing.is_active:
                    raise RuntimeError(
                        f"Existing {email} has unexpected role or status; resolve explicitly"
                    )
                continue
            crud.create_user(
                session=session,
                user_create=UserCreate(
                    email=email,
                    password=password,
                    full_name=f"Demo {role.value.title()}",
                    role=role,
                ),
            )
        admin = crud.get_user_by_email(session=session, email=settings.FIRST_SUPERUSER)
        if admin is None or admin.role != Role.ADMIN or not admin.is_active:
            raise RuntimeError("Configured initial admin has unexpected role or status")


if __name__ == "__main__":
    main()
