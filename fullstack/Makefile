SHELL := /bin/bash
.PHONY: install db migrate seed backend frontend test check client

install:
	uv sync --frozen
	bun install --frozen-lockfile

db:
	docker compose -f compose.local.yml up -d --wait

migrate:
	cd backend && uv run alembic upgrade head

seed:
	cd backend && uv run --env-file ../.env python -m app.seed_demo

backend:
	cd backend && FASTAPI_ENV=development uv run uvicorn app.main:app --host 127.0.0.1 --port 8001

frontend:
	cd frontend && bun run dev -- --host 127.0.0.1 --port 5174

# tests/conftest.py deletes users/items at teardown. An explicitly separate DB is mandatory.
test:
	@test -n "$(TEST_DATABASE_URL)" || (echo 'Set TEST_DATABASE_URL to an isolated disposable database'; exit 1)
	cd backend && DATABASE_URL='$(TEST_DATABASE_URL)' uv run alembic upgrade head
	cd backend && FASTAPI_ENV=development DATABASE_URL='$(TEST_DATABASE_URL)' uv run pytest -q

check:
	cd backend && uv run ruff check app tests && uv run ruff format --check app tests && uv run mypy app && uv run ty check app
	cd frontend && bun run build

client:
	cd backend && FASTAPI_ENV=development uv run python -c 'import json; from app.main import app; print(json.dumps(app.openapi()))' > ../frontend/openapi.json
	cd frontend && bun run generate-client
