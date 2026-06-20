# Poker Bot Stage 13 — Telegram/MAX shared game core

## Decision

Do not patch the current Telegram flow with more message spam. Rebuild the interaction layer around a platform-neutral game state machine.

## Canonical game logic

### Solo `/cards`

- No table cards.
- Player gets exactly 5 cards.
- Player may select 0, 1, or 2 cards to exchange.
- Selection is manual: each card has its own button.
- A third selected card is rejected with a private callback alert.
- Only the owner of the hand may press hand buttons.
- Selection edits the same message, never sends a new one.
- Final result edits the same message.
- Session TTL: 5 minutes.
- After TTL, callbacks return an expired-session alert.

### Duel `/duel @username`

- Available only in group chats.
- Request TTL: 5 minutes.
- Only the target player can accept.
- Only duel participants can decline.
- One user cannot have multiple pending/active duels in the same chat.
- After accept: table appears only in duel mode.
- Duel uses 5 table cards + 2 private cards for each player.
- Each player may select 0, 1, or 2 private cards to exchange.
- Only the owner may press their card buttons.
- Selection edits the same personal-choice message.
- Result is sent once when both players are ready.
- Duel state TTL: 5 minutes.

## UI rules

- No extra messages on every card click.
- Active selection screens do not show unnecessary back/menu buttons.
- Menus should be compact and consistent.
- Nickname editing is only in profile.
- Leaderboards show public game nick, not Telegram username.
- Top icons:
  - game top: trophy
  - duel top: shield/crossed-swords, not same icon as duel action

## Platform adapter contract

All game actions must call a small platform interface:

- send_message(chat_id, text, keyboard)
- edit_message(chat_id, message_id, text, keyboard)
- answer_callback(callback_id, text, alert)
- get_actor_id(update)
- get_chat_id(update)
- get_chat_type(update)
- get_text_or_callback(update)

Telegram and MAX adapters must only translate this contract to platform APIs.

## MAX mapping

- send_message -> POST /messages
- edit_message -> PUT /messages/{messageId}
- answer_callback -> POST callback answer method
- keyboard -> inline_keyboard attachment with callback buttons
- production updates -> Webhook subscription on HTTPS 443
- dev updates -> Long Polling only for tests
- auth -> Authorization header, no query token

## Next implementation stages

### Stage 13A — Telegram clean UX

- Replace current Telegram callback handling with edit-message flow.
- Store classic session message_id.
- Store duel selection message_id per participant where possible.
- Remove duplicate per-click messages.
- Keep solo mode table-free.

### Stage 13B — Shared game service

- Move session logic from telegram.py into app/game/sessions.py.
- Add platform-neutral action results.
- Add tests for solo draw and duel state machine.

### Stage 13C — MAX adapter skeleton

- Add app/bot/max.py.
- Add /webhooks/max real handler.
- Add MAX API client wrapper.
- Implement send/edit/callback/keyboard mapping.
- Keep disabled until MAX_BOT_TOKEN and webhook domain are configured.

### Stage 13D — Admin rules

- Per-chat limits.
- Per-chat combo scoring overrides.
- Per-chat leaderboard limits.
- Global defaults.
- Audit log for every admin change.

## Security and reliability

- Never log tokens.
- Never commit .env.
- Callback ownership checks on every button.
- Rate limit /cards and callback spam.
- Pending state must move to Redis before multiple workers.
- SQLite is stage-only. Production should move to PostgreSQL.
