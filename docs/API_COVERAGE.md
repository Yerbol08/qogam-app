# Покрытие Swagger — 10 октября 2026

API 0.3.1: **119 из 119 операций** зарегистрированы в клиенте.
Источник: [openapi.json](openapi.json). Генератор: [generate_contract.py](../tool/generate_contract.py).
Сгенерированный контракт: [api_contract.g.dart](../lib/api_contract.g.dart).
Транспорт и проверка DTO: [api_contract.dart](../lib/api_contract.dart), [backend.dart](../lib/backend.dart).

Обновление схемы: заменить `docs/openapi.json`, выполнить `python3 tool/generate_contract.py`, затем `flutter test test/contract_test.dart`.
Тест сверяет полный набор методов, параметры, схемы и требования авторизации с исходным Swagger; каждый endpoint проходит отдельную проверку HTTP-запроса на MockClient. Реальные мутации эти тесты не выполняют.

Пользовательские разделы:
- «Рядом» / «Мои заявки»: реальные проблемы, подача и правка, история, присоединение и отмена, обратная связь и жалобы, поиск адреса и похожих проблем.
- «Сервисы» (значок уведомлений сверху или пункт профиля): уведомления, счётчик, прочтение одного/всех, настройки тихих часов, объявления и история, подписки, членство, приглашения и приватные заявки ОСИ.
- «Мой дом»: карточка, контакты, вступление, новости, заявки и отдельное подтверждение публичной публикации. Управление домами и новости сотрудников доступны из карточки дома.
- Профиль: аккаунт, согласия, устройства и места; сотрудникам доступны настройка MFA, рабочий кабинет и администрирование по роли. Дополнительные полномочия и принадлежность организации проверяет сервер.
- Фото: выбор из галереи, multipart с постоянным `client_media_id` для повтора, статус обработки, чтение и удаление непривязанного фото. Сотрудникам доступны одобрение и маскирование прямоугольников в пикселях. Для фото результата используется `result_photo`.

Формы строятся по DTO: числовые ограничения, enum, nullable, вложенные объекты, массивы и варианты действий. PATCH позволяет отдельно не менять поле, очистить его или передать значение. Версия записи подставляется из ответа сервера; ID новой заявки генерируется один раз. Неопределённый результат подачи приватной заявки хранится в защищённом хранилище по аккаунту, origin и дому; повтор отправляет прежний payload. Географические контуры вводятся координатами вершин. Справочники выбираются из списков; ручной ввод кода остаётся доступным, например когда запись не попала в первую страницу списка.

API покрыт на уровне клиента и экранов. Проверка прав, переходов статуса, идемпотентности и обработанных фото на реальном сервере требует тестовых аккаунтов. Автоматическое получение Firebase/APNs-токена не является endpoint Swagger и требует конфигурации проекта push-провайдера; API регистрации/отключения настоящего токена подключён.

Известное расхождение: Swagger помечает GET /v1/houses как Bearer, но сервер допускает анонимное чтение безопасного списка. Универсальный клиент следует Swagger; главный экран использует существующее анонимное чтение, а действия дома требуют входа.

| Метод | Endpoint | Раздел Swagger | Авторизация по схеме |
| --- | --- | --- | --- |
| POST | `/v1/auth/otp/request` | auth | Без обязательного входа |
| POST | `/v1/auth/otp/verify` | auth | Без обязательного входа |
| POST | `/v1/auth/refresh` | auth | Без обязательного входа |
| POST | `/v1/auth/logout` | auth | Без обязательного входа |
| POST | `/v1/auth/mfa/setup` | auth | Bearer |
| POST | `/v1/auth/mfa/confirm` | auth | Bearer |
| GET | `/v1/me` | me | Bearer |
| DELETE | `/v1/me` | me | Bearer |
| PATCH | `/v1/me` | me | Bearer |
| GET | `/v1/me/export` | me | Bearer |
| GET | `/v1/me/consents` | me | Bearer |
| PUT | `/v1/me/consents/{purpose}` | me | Bearer |
| PUT | `/v1/me/devices` | me | Bearer |
| DELETE | `/v1/me/devices` | me | Bearer |
| GET | `/v1/me/places` | me | Bearer |
| POST | `/v1/me/places` | me | Bearer |
| PATCH | `/v1/me/places/{place_id}` | me | Bearer |
| DELETE | `/v1/me/places/{place_id}` | me | Bearer |
| GET | `/v1/meta` | reference | Без обязательного входа |
| GET | `/v1/categories` | reference | Без обязательного входа |
| GET | `/v1/cities` | reference | Без обязательного входа |
| GET | `/v1/cities/{city_code}` | reference | Без обязательного входа |
| GET | `/v1/statuses` | reference | Без обязательного входа |
| GET | `/v1/legal/documents` | reference | Без обязательного входа |
| GET | `/v1/problems` | problems | Без обязательного входа |
| GET | `/v1/problems/map` | problems | Без обязательного входа |
| GET | `/v1/problems/similar` | problems | Без обязательного входа |
| GET | `/v1/problems/{problem_id}` | problems | Bearer |
| GET | `/v1/problems/{problem_id}/history` | problems | Без обязательного входа |
| POST | `/v1/problems/{problem_id}/join` | problems | Bearer |
| DELETE | `/v1/problems/{problem_id}/join` | problems | Bearer |
| POST | `/v1/problems/{problem_id}/feedback` | problems | Bearer |
| POST | `/v1/problems/{problem_id}/flags` | problems | Bearer |
| POST | `/v1/reports` | reports | Bearer |
| GET | `/v1/me/reports` | reports | Bearer |
| GET | `/v1/me/reports/by-client-request/{client_request_id}` | reports | Bearer |
| GET | `/v1/me/reports/{report_id}` | reports | Bearer |
| PATCH | `/v1/me/reports/{report_id}` | reports | Bearer |
| GET | `/v1/me/reports/{report_id}/history` | reports | Bearer |
| POST | `/v1/me/reports/{report_id}/clarifications` | reports | Bearer |
| POST | `/v1/me/reports/{report_id}/withdraw` | reports | Bearer |
| GET | `/v1/me/joined-problems` | reports | Bearer |
| GET | `/v1/me/subscriptions/problems` | subscriptions | Bearer |
| PUT | `/v1/me/subscriptions/problems/{problem_id}` | subscriptions | Bearer |
| DELETE | `/v1/me/subscriptions/problems/{problem_id}` | subscriptions | Bearer |
| POST | `/v1/media` | media | Bearer |
| GET | `/v1/media/{media_id}` | media | Bearer |
| DELETE | `/v1/media/{media_id}` | media | Bearer |
| GET | `/v1/staff/reports` | staff | Bearer |
| GET | `/v1/staff/reports/{report_id}` | staff | Bearer |
| POST | `/v1/staff/reports/{report_id}/actions` | staff | Bearer |
| GET | `/v1/staff/problems` | staff | Bearer |
| GET | `/v1/staff/problems/{problem_id}` | staff | Bearer |
| POST | `/v1/staff/problems/{problem_id}/actions` | staff | Bearer |
| POST | `/v1/staff/media/{media_id}/approve` | staff | Bearer |
| POST | `/v1/staff/media/{media_id}/redact` | staff | Bearer |
| GET | `/v1/me/notifications` | notifications | Bearer |
| GET | `/v1/me/notifications/unread-count` | notifications | Bearer |
| PUT | `/v1/me/notifications/{notification_id}/read` | notifications | Bearer |
| POST | `/v1/me/notifications/read-all` | notifications | Bearer |
| GET | `/v1/me/notification-settings` | notifications | Bearer |
| PUT | `/v1/me/notification-settings` | notifications | Bearer |
| GET | `/v1/alerts` | alerts | Без обязательного входа |
| GET | `/v1/alerts/{alert_id}` | alerts | Без обязательного входа |
| GET | `/v1/alerts/{alert_id}/history` | alerts | Без обязательного входа |
| POST | `/v1/staff/alerts` | alerts | Bearer |
| GET | `/v1/staff/alerts/{alert_id}` | alerts | Bearer |
| PATCH | `/v1/staff/alerts/{alert_id}` | alerts | Bearer |
| POST | `/v1/staff/alerts/{alert_id}/preview` | alerts | Bearer |
| POST | `/v1/staff/alerts/{alert_id}/publish` | alerts | Bearer |
| POST | `/v1/staff/alerts/{alert_id}/cancel` | alerts | Bearer |
| GET | `/v1/geo/search` | geo | Без обязательного входа |
| GET | `/v1/geo/reverse` | geo | Без обязательного входа |
| GET | `/v1/houses` | my home | Bearer |
| GET | `/v1/houses/{house_id}` | my home | Bearer |
| GET | `/v1/me/house-memberships` | my home | Bearer |
| POST | `/v1/houses/{house_id}/membership-requests` | my home | Bearer |
| DELETE | `/v1/me/house-memberships/{membership_id}` | my home | Bearer |
| GET | `/v1/me/house-invitations` | my home | Bearer |
| POST | `/v1/me/house-invitations/{invitation_id}/accept` | my home | Bearer |
| POST | `/v1/me/house-invitations/{invitation_id}/decline` | my home | Bearer |
| GET | `/v1/houses/{house_id}/news` | my home | Bearer |
| GET | `/v1/houses/{house_id}/news/{news_id}` | my home | Bearer |
| POST | `/v1/houses/{house_id}/requests` | my home | Bearer |
| GET | `/v1/me/house-requests` | my home | Bearer |
| GET | `/v1/me/house-requests/{request_id}` | my home | Bearer |
| GET | `/v1/me/house-requests/{request_id}/history` | my home | Bearer |
| POST | `/v1/me/house-requests/{request_id}/clarifications` | my home | Bearer |
| POST | `/v1/me/house-requests/{request_id}/withdraw` | my home | Bearer |
| POST | `/v1/me/house-requests/{request_id}/publication-confirmations` | my home | Bearer |
| GET | `/v1/staff/houses/{house_id}/membership-requests` | my home | Bearer |
| POST | `/v1/staff/house-membership-requests/{membership_id}/decisions` | my home | Bearer |
| POST | `/v1/staff/houses/{house_id}/invitations` | my home | Bearer |
| POST | `/v1/staff/houses/{house_id}/news` | my home | Bearer |
| PATCH | `/v1/staff/houses/{house_id}/news/{news_id}` | my home | Bearer |
| POST | `/v1/staff/houses/{house_id}/news/{news_id}/unpublish` | my home | Bearer |
| GET | `/v1/staff/house-requests` | my home | Bearer |
| POST | `/v1/staff/house-requests/{request_id}/actions` | my home | Bearer |
| GET | `/v1/admin/categories` | admin | Bearer |
| POST | `/v1/admin/categories` | admin | Bearer |
| PATCH | `/v1/admin/categories/{code}` | admin | Bearer |
| GET | `/v1/admin/cities` | admin | Bearer |
| POST | `/v1/admin/cities` | admin | Bearer |
| PATCH | `/v1/admin/cities/{code}` | admin | Bearer |
| GET | `/v1/admin/organizations` | admin | Bearer |
| POST | `/v1/admin/organizations` | admin | Bearer |
| PATCH | `/v1/admin/organizations/{organization_id}` | admin | Bearer |
| GET | `/v1/admin/routing-zones` | admin | Bearer |
| POST | `/v1/admin/routing-zones` | admin | Bearer |
| PATCH | `/v1/admin/routing-zones/{zone_id}` | admin | Bearer |
| GET | `/v1/admin/houses` | admin | Bearer |
| POST | `/v1/admin/houses` | admin | Bearer |
| PATCH | `/v1/admin/houses/{house_id}` | admin | Bearer |
| GET | `/v1/admin/staff` | admin | Bearer |
| POST | `/v1/admin/staff` | admin | Bearer |
| PATCH | `/v1/admin/staff/{user_id}` | admin | Bearer |
| DELETE | `/v1/admin/staff/{user_id}` | admin | Bearer |
| POST | `/v1/admin/user-restrictions` | admin | Bearer |
| GET | `/v1/admin/audit-events` | admin | Bearer |

Проверки этого этапа: 163 автоматических теста прошли, сетевой smoke test ru/kk прошёл отдельно; flutter analyze без замечаний, форматирование и git diff --check чистые. Debug APK собран: `build/app/outputs/flutter-apk/app-debug.apk`. iOS и native photo picker на физическом устройстве не проверены.
