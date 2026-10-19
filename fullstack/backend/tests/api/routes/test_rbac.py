import uuid

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session

from app import crud
from app.core.config import settings
from app.models import User, UserCreate
from app.permissions import Role, permissions_for

API = settings.API_V1_STR
PASSWORD = "Rbac-test-password-32"


def account(client: TestClient, db: Session, role: Role) -> tuple[User, dict[str, str]]:
    user = crud.create_user(
        session=db,
        user_create=UserCreate(
            email=f"{uuid.uuid4()}@example.com", password=PASSWORD, role=role
        ),
    )
    login = client.post(
        f"{API}/login/access-token", data={"username": user.email, "password": PASSWORD}
    )
    assert login.status_code == 200
    return user, {"Authorization": f"Bearer {login.json()['access_token']}"}


@pytest.mark.parametrize("role", list(Role))
def test_permission_matrix(client: TestClient, db: Session, role: Role) -> None:
    user, headers = account(client, db, role)
    me = client.get(f"{API}/users/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["permissions"] == permissions_for(role)
    assert "is_superuser" not in me.json()
    assert "hashed_password" not in me.json()
    read_status = 403 if role == Role.MEMBER else 200
    assert client.get(f"{API}/users/", headers=headers).status_code == read_status
    assert client.get(f"{API}/metrics/", headers=headers).status_code == read_status
    new_email = f"{uuid.uuid4()}@example.com"
    response = client.post(
        f"{API}/users/",
        headers=headers,
        json={"email": new_email, "password": PASSWORD, "role": "manager"},
    )
    assert response.status_code == (200 if role == Role.ADMIN else 403)
    assert (crud.get_user_by_email(session=db, email=new_email) is not None) == (
        role == Role.ADMIN
    )
    assert (
        client.patch(
            f"{API}/users/me", headers=headers, json={"full_name": "My updated name"}
        ).status_code
        == 200
    )
    db.refresh(user)
    assert user.full_name == "My updated name"
    assert user.role == role
    # Ordinary app features remain available to every role.
    assert (
        client.post(
            f"{API}/items/", headers=headers, json={"title": "My item"}
        ).status_code
        == 200
    )


@pytest.mark.parametrize("role", [Role.MEMBER, Role.MANAGER])
def test_non_admin_cannot_change_another_user(
    client: TestClient, db: Session, role: Role
) -> None:
    _, headers = account(client, db, role)
    target, _ = account(client, db, Role.MEMBER)
    assert (
        client.patch(
            f"{API}/users/{target.id}", headers=headers, json={"role": "admin"}
        ).status_code
        == 403
    )
    assert client.delete(f"{API}/users/{target.id}", headers=headers).status_code == 403
    assert client.get(f"{API}/users/{target.id}", headers=headers).status_code == (
        200 if role == Role.MANAGER else 403
    )
    db.refresh(target)
    assert target.role == Role.MEMBER


@pytest.mark.parametrize(
    "payload",
    [
        {"role": "admin"},
        {"is_superuser": True},
        {"is_active": True},
        {"permissions": ["users:write"]},
    ],
)
def test_self_profile_rejects_privilege_injection(
    client: TestClient, db: Session, payload: dict
) -> None:
    user, headers = account(client, db, Role.MEMBER)
    assert (
        client.patch(f"{API}/users/me", headers=headers, json=payload).status_code
        == 422
    )
    db.refresh(user)
    assert user.role == Role.MEMBER


def test_signup_cannot_choose_role(client: TestClient, db: Session) -> None:
    email = f"{uuid.uuid4()}@example.com"
    data = {"email": email, "password": PASSWORD}
    for extra in ({"role": "admin"}, {"is_superuser": True}):
        assert client.post(f"{API}/users/signup", json=data | extra).status_code == 422
        assert crud.get_user_by_email(session=db, email=email) is None
    response = client.post(f"{API}/users/signup", json=data)
    assert response.status_code == 200
    assert response.json()["role"] == "member"


def test_role_change_and_deactivation_apply_to_existing_token(
    client: TestClient, db: Session
) -> None:
    _, admin_headers = account(client, db, Role.ADMIN)
    user, headers = account(client, db, Role.MANAGER)
    assert client.get(f"{API}/metrics/", headers=headers).status_code == 200
    assert (
        client.patch(
            f"{API}/users/{user.id}", headers=admin_headers, json={"role": "member"}
        ).status_code
        == 200
    )
    assert client.get(f"{API}/metrics/", headers=headers).status_code == 403
    assert client.get(f"{API}/users/me", headers=headers).json()["permissions"] == []
    assert (
        client.patch(
            f"{API}/users/{user.id}", headers=admin_headers, json={"is_active": False}
        ).status_code
        == 200
    )
    assert client.get(f"{API}/users/me", headers=headers).status_code == 403


@pytest.mark.parametrize(
    "payload",
    [{"role": "owner"}, {"role": None}, {"is_superuser": True}, {"is_active": None}],
)
def test_admin_cannot_store_invalid_privileges(
    client: TestClient, db: Session, payload: dict
) -> None:
    _, headers = account(client, db, Role.ADMIN)
    target, _ = account(client, db, Role.MEMBER)
    assert (
        client.patch(
            f"{API}/users/{target.id}", headers=headers, json=payload
        ).status_code
        == 422
    )
    db.refresh(target)
    assert target.role == Role.MEMBER
    assert target.is_active


@pytest.mark.parametrize("path", ["/users/", "/users/me", "/metrics/"])
def test_protected_surfaces_require_authentication(
    client: TestClient, path: str
) -> None:
    assert client.get(f"{API}{path}").status_code == 401


def test_legacy_development_user_creation_removed(client: TestClient) -> None:
    response = client.post(
        f"{API}/private/users/",
        json={
            "email": "intruder@example.com",
            "password": PASSWORD,
            "full_name": "Intruder",
        },
    )
    assert response.status_code == 404
    assert "location" not in response.headers
