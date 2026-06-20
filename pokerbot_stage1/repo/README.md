# poker-bot

Модульный poker-bot backend для Telegram, MAX, Mini App и внутренней админки.

## Цель

- Telegram bot.
- MAX bot.
- Telegram Mini App.
- MAX Mini App.
- Общая база игроков.
- Личные и групповые очки.
- Дуэльные очки.
- Мировой рейтинг.
- Достижения.
- Админка для блокировок, баллов, чатов, пользователей и аудита.
- Модульная система под будущие карточные игры.

## Security baseline

- Токены не хранятся в Git.
- `.env` только на сервере/хостинге.
- Webhooks production только через HTTPS.
- Telegram webhook secret проверяется через `X-Telegram-Bot-Api-Secret-Token`.
- MAX webhook secret проверяется через `X-Max-Bot-Api-Secret`.
- Mini App авторизация только через подписанный `initData`.
- Телефон/email — только дополнительная привязка, не первичный вход.
- Админка должна быть закрыта VPN/reverse-proxy allowlist.

## Текущий stage

- FastAPI backend.
- Telegram/MAX webhook stubs.
- Mini App placeholder.
- Admin API stub.
- Game engine: карты, комбинации, classic draw, holdem duel scoring.
- Tests.
