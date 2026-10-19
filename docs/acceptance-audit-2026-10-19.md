# Проверка первого задания по спеке

Дата: 19 октября 2026 года. Проверка исходного состояния `70b780b` и исправлений в ветке `fix/evios-spec-acceptance` относительно [спеки](specs/2026-10-19-evios.md). Ghost и выделенный VPS не входят в проверку.

## Найденные и исправленные недочёты

| ID | Недочёт и подтверждение | Исправление | Проверка |
| --- | --- | --- | --- |
| F1 | У admin отображалась вкладка Danger zone и действие удаления аккаунта, хотя API запрещает это действие. Ветка `slice(0, 3)` возвращала все три вкладки | Вкладка удаления исключается для admin; для member/manager остаётся | Браузерная проверка отсутствия вкладки и заголовка удаления; desktop/mobile screenshots |
| F2 | `PATCH /users/me` с `email: null` проходил Pydantic, затем нарушал NOT NULL в PostgreSQL и возвращал 500. Аналогичная проблема существовала у административных null email/password | Явный null отклоняется входной схемой с 422; отсутствующее поле по-прежнему означает «не менять» | Три роли для своего профиля, два административных поля; проверка неизменности данных и доступности профиля после отказа |
| F3 | Подписанный JWT с невалидным UUID в `sub` доходил до SQLAlchemy и давал 500 вместо 401 | `TokenPayload.sub` — обязательный UUID; ошибка перехватывается существующей обработкой ValidationError | Четыре варианта некорректного/неизвестного subject дают 401 |
| F4 | Guards отдельно загружали `/users/me`, а навигация и кнопки использовали другой query текущего пользователя. Решения о доступе могли вычисляться по разным снимкам роли | Защищённый layout обновляет общий query cache перед навигацией; дочерние guards читают результат родителя, useAuth использует те же query options | Admin → manager → member в одном сеансе: исчезают create/edit/delete и пункты Users/Metrics, появляется Access denied, сеанс и свои Settings сохраняются |
| F5 | Повторный admin-прогон падал: поиск `Updated Name` находил строки от предыдущего запуска | Утверждение ограничено строкой конкретного пользователя по уникальному email | Повторные browser-прогоны проходят без очистки чужих/демонстрационных данных |

F3 — ошибка обработки некорректного токена, а не доказательство возможности подделать подпись или повысить права. При F2 невалидная запись не сохранялась: транзакция откатывалась. Исправления не добавляют новые роли или разрешения.

## Матрица приёмки после исправлений

| Критерий | Результат | Проверенное доказательство |
| --- | --- | --- |
| A1 — запуск по README | Passed | Lockfile install, миграции/seed и dev-серверы; статические проверки и production build |
| A2 — каноническая роль и миграция | Passed | Новая отдельная `evios_audit_migration`: старые admin/member, отсутствие boolean, CHECK, manager downgrade и повторный upgrade |
| A3 — управление пользователями admin | Passed | API matrix и browser create/edit/delete/role assignment |
| A4 — manager только читает | Passed | API 200/403; browser после понижения роли: Users виден, Add User отсутствует, кнопок в таблице нет |
| A5 — свой профиль и основные функции | Passed | API тесты всех ролей; создание собственного Item; UI Settings после понижения до member |
| A6 — member без Users/Metrics | Passed | API 403; прямой `/admin` и переход `/metrics` показывают Access denied, пункты скрыты |
| A7 — нет повышения прав через signup/profile | Passed | Действующие regression-тесты reject extra fields и проверка роли в БД |
| A8 — недопустимые роли и null | Passed | Валидация роли/активности; новые null profile/admin tests; прямое нарушение CHECK отклонено БД |
| A9 — старый JWT теряет отозванные права | Passed | API role/deactivation test использует тот же токен; browser demotion без повторного login |
| A10 — согласованный cache и сохранение сеанса при 403 | Passed | Общий cache из loader; один browser context после смены роли; Settings доступны после отказа |
| A11 — удалённый API даёт 404 | Passed | Повторно проверены GET/POST в development и production: 404, без Location, JSON |
| A12 — desktop/mobile | Passed | Визуально проверены admin Settings на 1200 px и 390 px; предыдущие Users/Metrics/denial screenshots сохраняются в отчёте |
| A13 — автоматические проверки | Passed | 88 pytest, 15 Chromium browser checks, Ruff, mypy, ty, TypeScript/Vite; OpenAPI client без drift |
| A14 — приватный репозиторий и состав сдачи | Passed | PR #1 открыт в main из отдельной ветки; GitHub подтвердил PRIVATE и совпадение кода PR с локальным коммитом; AI dialogue обновлён |
| A15 — Ghost отдельно | Passed | Код и VPS Ghost не изменялись |

## Выполненные команды и результаты

Из `fullstack/`:

```sh
TEST_DATABASE_URL=postgresql://postgres:evios-local-only@127.0.0.1:55433/evios_test make test
make check
make client
```

Результат backend: **88 passed**, 7,68 с; один upstream warning Starlette TestClient/httpx. Генерация клиента не изменила закоммиченный API-клиент.

Для одновременной проверки с уже запущенным экземпляром использованы отдельные dev-порты API `8002` и UI `5175`; стандартные команды README остаются на `8001`/`5174`.

```sh
# backend/
FASTAPI_ENV=development FRONTEND_HOST=http://127.0.0.1:5175 \
  uv run uvicorn app.main:app --host 127.0.0.1 --port 8002

# frontend/
VITE_API_URL=http://127.0.0.1:8002 bun run dev -- --host 127.0.0.1 --port 5175
PLAYWRIGHT_BASE_URL=http://127.0.0.1:5175 VITE_API_URL=http://127.0.0.1:8002 \
  bunx playwright test tests/admin.spec.ts --project=chromium --workers=1 --reporter=line
```

Последний browser-прогон: **15 passed**, 16,1 с, включая setup. Добавлены проверки запрета самостоятельного удаления admin и изменений роли в том же browser session. Доступные для manager пункты и действия проверяются реальным API, а не mocked permissions.

Демонстрационные admin/member/manager сохранены. Тест изменений роли создаёт собственный временный аккаунт и удаляет его в finally. Полный набор unrelated frontend-тестов, SMTP-доставка и внешний production deployment не выполнялись; эти результаты не заявляются.

## Скриншоты

- [Admin Settings: desktop](screenshots/audit/audit-admin-settings.png).
- [Admin Settings: mobile 390 × 844](screenshots/audit/audit-admin-settings-mobile.png).
- [Остальные браузерные доказательства первого прогона](verification.md).

## Передача на ревью

Исправления оформляются PR в `main`; сама `main` до ревью не изменяется. В PR запрашивается `@codex review` с ссылкой на эту матрицу и спеку. Запрос ревью не считается завершённым ревью. PR не сливается автоматически.


## Завершающая проверка

Чистый клон ветки исправлений: установка по lock-файлам, `make check` и полный backend-набор с `.env.example` прошли. Результат pytest в чистом клоне: **88 passed**, 20,36 с. Новые source-файлы общего cache присутствуют в Git; локальный глобальный ignore `lib` не влияет на состав сдачи.

[PR #1](https://github.com/xen/evios-test-tasks/pull/1) открыт в `main`, репозиторий PRIVATE. Ревью Codex запрашивается отдельным комментарием после последней отправки материалов. PR не слит.
