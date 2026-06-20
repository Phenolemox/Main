#!/usr/bin/env bash
set -euo pipefail
cd /opt/repos/poker-bot
git fetch origin main || true
git checkout main || git checkout -b main
git pull --rebase origin main || true
python3 - <<'PY'
from pathlib import Path
p = Path('app/bot/telegram.py')
s = p.read_text(encoding='utf-8')
# active selection: no menu button
s = s.replace("[{'text': '🎲 Играть', 'callback_data': f'classic_done:{session_id}'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]", "[{'text': '🎲 Играть', 'callback_data': f'classic_done:{session_id}'}]")
s = s.replace("[{'text': '🎲 Готов', 'callback_data': f'duel_done:{duel_id}'}, {'text': '⬅️ Меню', 'callback_data': 'menu'}]", "[{'text': '🎲 Готов', 'callback_data': f'duel_done:{duel_id}'}]")
# add edit helper
if 'async def edit_telegram_message(' not in s:
    marker = '\n\nasync def answer_callback_query('
    helper = '''\n\nasync def edit_telegram_message(chat_id, message_id, text, *, reply_markup=None):\n    token = get_settings().telegram_bot_token or ''\n    if not token:\n        return {'dry_run': True}\n    payload = {'chat_id': chat_id, 'message_id': message_id, 'text': text, 'disable_web_page_preview': True}\n    if reply_markup:\n        payload['reply_markup'] = reply_markup\n    url = 'https://api.telegram.org/' + 'bot' + token + '/editMessageText'\n    async with httpx.AsyncClient(timeout=15) as client:\n        response = await client.post(url, json=payload)\n    return {'status_code': response.status_code, 'ok': response.is_success}\n'''
    s = s.replace(marker, helper + marker, 1)
# classic toggle edits same message
old = "return [await send_telegram_message(chat_id, f\"☠️ Твоя рука:\\n{format_cards(s.hand)}\\nВыбрано: {len(s.selected)}/2\", reply_markup=classic_keyboard(s.session_id, s.hand, s.selected))]"
new = "await edit_telegram_message(chat_id, int(msg.get('message_id') or 0), f\"☠️ Твоя рука:\\n{format_cards(s.hand)}\\n\\nВыбери до 2 карт для обмена или жми 🎲 Играть.\\nВыбрано: {len(s.selected)}/2\", reply_markup=classic_keyboard(s.session_id, s.hand, s.selected)); return []"
s = s.replace(old, new)
old = "return [await send_telegram_message(chat_id, f\"☠️ Твоя рука:\\n{format_cards(s.hand)}\\n\\nВыбрано: {len(s.selected)}/2\", reply_markup=classic_keyboard(s.session_id, s.hand, s.selected))]"
s = s.replace(old, new)
# classic done edits same message
s = s.replace("return [await _finish_classic(db, chat_id, user.id, sid)]", "return [await _finish_classic(db, chat_id, int(msg.get('message_id') or 0), user.id, sid)]")
s = s.replace("async def _finish_classic(db: AsyncSession, chat_id: str, user_id: int, session_id: str) -> dict:", "async def _finish_classic(db: AsyncSession, chat_id: str, message_id: int, user_id: int, session_id: str) -> dict:")
s = s.replace("return await send_telegram_message(chat_id, '⏱️ Раздача устарела. Нажми /cards.', reply_markup=result_keyboard())", "return await edit_telegram_message(chat_id, message_id, '⏱️ Раздача устарела. Нажми /cards.', reply_markup=result_keyboard())")
s = s.replace("return await send_telegram_message(chat_id, f\"☠️ Итоговая рука:\\n{format_cards(s.hand)}{removed_text}\\n{result.name} ({result.points} очков)\\n{PHRASES[result.name]}\", reply_markup=result_keyboard(s.chat_type))", "return await edit_telegram_message(chat_id, message_id, f\"☠️ Итоговая рука:\\n{format_cards(s.hand)}{removed_text}\\n{result.name} ({result.points} очков)\\n{PHRASES[result.name]}\", reply_markup=result_keyboard(s.chat_type))")
# duel personal toggle edits same message
old = "return [await send_telegram_message(chat_id, f\"🃏 Твои карты:\\n{format_cards(hand)}\\nВыбрано: {len(d.selected[user.id])}/2\", reply_markup=duel_personal_keyboard(d.duel_id, hand, d.selected[user.id]))]"
new = "await edit_telegram_message(chat_id, int(msg.get('message_id') or 0), f\"🃏 Твои карты:\\n{format_cards(hand)}\\nВыбрано: {len(d.selected[user.id])}/2\", reply_markup=duel_personal_keyboard(d.duel_id, hand, d.selected[user.id])); return []"
s = s.replace(old, new)
old = "return [await send_telegram_message(chat_id, f\"✅ Выбор принят.\\nГотовы: {sum(1 for v in d.ready.values() if v)}/2\")]"
new = "await edit_telegram_message(chat_id, int(msg.get('message_id') or 0), f\"✅ Выбор принят.\\nГотовы: {sum(1 for v in d.ready.values() if v)}/2\"); return []"
s = s.replace(old, new)
p.write_text(s, encoding='utf-8')
PY
./.venv/bin/python -m py_compile $(find app -name '*.py')
./.venv/bin/python -m pytest -q
git add .
git commit -m 'Patch telegram selection editing stage12' || true
git push -u origin main
ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health
curl -s --max-time 5 http://10.8.0.1:8140/health && echo
echo 'STAGE12_MIN_DONE'
