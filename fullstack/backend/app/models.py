import uuid
from datetime import UTC, datetime

from pydantic import EmailStr, computed_field, field_validator
from sqlalchemy import CheckConstraint
from sqlalchemy import Enum as SAEnum
from sqlmodel import Field, Relationship, SQLModel
from sqlmodel._compat import SQLModelConfig

from app.permissions import Permission, Role, permissions_for


def get_datetime_utc() -> datetime:
    return datetime.now(UTC)


# Shared properties
class UserBase(SQLModel):
    email: EmailStr = Field(unique=True, index=True, max_length=255)
    is_active: bool = True
    role: Role = Field(
        default=Role.MEMBER,
        sa_type=SAEnum(
            Role,
            native_enum=False,
            values_callable=lambda roles: [role.value for role in roles],
            length=16,
            validate_strings=True,
        ),
    )
    full_name: str | None = Field(default=None, max_length=255)


# Properties to receive via API on creation
class UserCreate(UserBase):
    model_config = SQLModelConfig(extra="forbid")
    password: str = Field(min_length=8, max_length=128)


class UserRegister(SQLModel):
    model_config = SQLModelConfig(extra="forbid")
    email: EmailStr = Field(max_length=255)
    password: str = Field(min_length=8, max_length=128)
    full_name: str | None = Field(default=None, max_length=255)


# Properties to receive via API on update, all are optional
class UserUpdate(SQLModel):
    model_config = SQLModelConfig(extra="forbid")
    email: EmailStr | None = Field(default=None, max_length=255)
    is_active: bool | None = None
    role: Role | None = None

    @field_validator("role", "is_active", "email", "password", mode="before")
    @classmethod
    def reject_null_updates(cls, value: object) -> object:
        if value is None:
            raise ValueError("This field cannot be null")
        return value

    full_name: str | None = Field(default=None, max_length=255)
    password: str | None = Field(default=None, min_length=8, max_length=128)


class UserUpdateMe(SQLModel):
    model_config = SQLModelConfig(extra="forbid")
    full_name: str | None = Field(default=None, max_length=255)
    email: EmailStr | None = Field(default=None, max_length=255)

    @field_validator("email", mode="before")
    @classmethod
    def reject_null_email(cls, value: object) -> object:
        if value is None:
            raise ValueError("Email cannot be null")
        return value


class UpdatePassword(SQLModel):
    current_password: str = Field(min_length=8, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


# Database model, database table inferred from class name
class User(UserBase, table=True):
    __table_args__ = (
        CheckConstraint(
            "role IN ('admin', 'manager', 'member')", name="user_role_check"
        ),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    hashed_password: str
    created_at: datetime | None = Field(default_factory=get_datetime_utc)
    items: list[Item] = Relationship(back_populates="owner", cascade_delete=True)


# Properties to return via API, id is always required
class UserPublic(UserBase):
    id: uuid.UUID
    created_at: datetime | None = None

    @computed_field  # type: ignore[prop-decorator]
    @property
    def permissions(self) -> list[Permission]:
        return permissions_for(self.role)


class UsersPublic(SQLModel):
    data: list[UserPublic]
    count: int


# Shared properties
class ItemBase(SQLModel):
    title: str = Field(min_length=1, max_length=255)
    description: str | None = Field(default=None, max_length=255)


# Properties to receive on item creation
class ItemCreate(ItemBase):
    pass


# Properties to receive on item update
class ItemUpdate(SQLModel):
    title: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = Field(default=None, max_length=255)


# Database model, database table inferred from class name
class Item(ItemBase, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    created_at: datetime | None = Field(default_factory=get_datetime_utc)
    owner_id: uuid.UUID = Field(
        foreign_key="user.id", nullable=False, ondelete="CASCADE"
    )
    owner: User | None = Relationship(back_populates="items")


# Properties to return via API, id is always required
class ItemPublic(ItemBase):
    id: uuid.UUID
    owner_id: uuid.UUID
    created_at: datetime | None = None


class ItemsPublic(SQLModel):
    data: list[ItemPublic]
    count: int


# Generic message
class Message(SQLModel):
    message: str


# JSON payload containing access token
class Token(SQLModel):
    access_token: str
    token_type: str = "bearer"


# Contents of JWT token
class TokenPayload(SQLModel):
    sub: uuid.UUID


class NewPassword(SQLModel):
    token: str
    new_password: str = Field(min_length=8, max_length=128)
