#!/usr/bin/env bash
set -euo pipefail
cd /opt/repos/poker-bot
LOG="/opt/logs/pokerbot_brand_stage16_$(date -u +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1

echo "===== POKER BOT BRAND STAGE16 UPLOAD ====="
echo "log=$LOG"

ZIP="/tmp/mypoker_brand_assets.zip"
if [ ! -f "$ZIP" ]; then
  echo "MISSING_ASSET_ZIP=$ZIP"
  echo "Upload mypoker_brand_assets.zip to /tmp/mypoker_brand_assets.zip via SFTP first."
  echo "POKER_BRAND_STAGE16_FAIL"
  exit 1
fi

git fetch origin main --quiet || true
git checkout main >/dev/null 2>&1 || git checkout -b main
git reset --hard origin/main >/dev/null
git clean -fd >/dev/null

mkdir -p static/branding
python3 - <<'PY'
from pathlib import Path
import shutil, zipfile
src = Path('/tmp/mypoker_brand_assets.zip')
dst = Path('/opt/repos/poker-bot/static/branding')
dst.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(src) as z:
    for name in z.namelist():
        if name.endswith('/'):
            continue
        base = Path(name).name
        if base in {'mypoker_avatar_512.jpg','mypoker_avatar_512.png','mypoker_welcome_1280x960.jpg'}:
            with z.open(name) as f, (dst / base).open('wb') as out:
                shutil.copyfileobj(f, out)
for need in ['mypoker_avatar_512.jpg','mypoker_welcome_1280x960.jpg']:
    if not (dst / need).exists():
        raise SystemExit(f'MISSING_IN_ZIP={need}')
print('BRAND_IMAGES_OK')
PY

python3 - <<'PY'
from pathlib import Path
p = Path('app/bot/telegram.py')
s = p.read_text(encoding='utf-8')
if 'from pathlib import Path' not in s:
    s = s.replace('import re\n', 'import re\nfrom pathlib import Path\n', 1)
if 'WELCOME_IMAGE_PATH' not in s:
    s = s.replace('NICK_RE = re.compile', "BASE_DIR = Path(__file__).resolve().parents[2]\nWELCOME_IMAGE_PATH = BASE_DIR / 'static' / 'branding' / 'mypoker_welcome_1280x960.jpg'\nNICK_RE = re.compile", 1)
if 'async def send_telegram_photo' not in s:
    marker = '\n\nasync def edit_telegram_message'
    helper = '''\n\nasync def send_telegram_photo(chat_id: str | int, photo_path: Path, caption: str, *, reply_markup: dict | None = None) -> dict:\n    token = get_settings().telegram_bot_token or ''\n    if not token or not photo_path.exists():\n        return await send_telegram_message(chat_id, caption, reply_markup=reply_markup)\n    data = {'chat_id': str(chat_id), 'caption': caption}\n    if reply_markup:\n        import json\n        data['reply_markup'] = json.dumps(reply_markup, ensure_ascii=False)\n    try:\n        async with httpx.AsyncClient(timeout=20) as client:\n            with photo_path.open('rb') as f:\n                response = await client.post('https://api.telegram.org/bot' + token + '/sendPhoto', data=data, files={'photo': (photo_path.name, f, 'image/jpeg')})\n        return {'status_code': response.status_code, 'ok': response.is_success}\n    except Exception:\n        return await send_telegram_message(chat_id, caption, reply_markup=reply_markup)\n'''
    s = s.replace(marker, helper + marker, 1)
s = s.replace("return [await send_telegram_message(chat_id, START_TEXT, reply_markup=main_keyboard(ctype))]", "return [await send_telegram_photo(chat_id, WELCOME_IMAGE_PATH, START_TEXT, reply_markup=main_keyboard(ctype))]")
p.write_text(s, encoding='utf-8')
print('BRAND_CODE_OK')
PY

cat > tests/test_brand_stage16.py <<'PY'
from pathlib import Path
from app.bot.telegram import WELCOME_IMAGE_PATH, main_keyboard


def test_welcome_image_path_name():
    assert isinstance(WELCOME_IMAGE_PATH, Path)
    assert WELCOME_IMAGE_PATH.name == 'mypoker_welcome_1280x960.jpg'


def test_main_menu_still_has_cards_and_duel():
    flat = [btn['callback_data'] for row in main_keyboard('private')['inline_keyboard'] for btn in row]
    assert 'cards' in flat
    assert 'duel_help' in flat
PY

./.venv/bin/python -m py_compile $(find app -name '*.py') >/tmp/stage16_pycompile.log 2>&1 || { echo PY_COMPILE_FAIL; tail -40 /tmp/stage16_pycompile.log; echo POKER_BRAND_STAGE16_FAIL; exit 1; }
echo "PY_COMPILE_OK"
./.venv/bin/python -m pytest -q >/tmp/stage16_pytest.log 2>&1 || { echo PYTEST_FAIL; tail -60 /tmp/stage16_pytest.log; echo POKER_BRAND_STAGE16_FAIL; exit 1; }
echo "PYTEST_OK"
tail -12 /tmp/stage16_pytest.log

python3 - <<'PY'
import asyncio
import httpx
from app.core.config import get_settings

async def main():
    token = get_settings().telegram_bot_token or ''
    if not token:
        print('BOT_DESCRIPTION_SKIPPED_NO_TOKEN')
        return
    short = 'Покерные раздачи, дуэли и рейтинги прямо в Telegram.'
    desc = 'MyPoker — винтажный покерный бот для раздач, дуэлей, лобби и рейтингов. Играй один, вызывай соперников и поднимайся в топах.'
    async with httpx.AsyncClient(timeout=15) as client:
        for method, payload in [
            ('setMyName', {'name': 'MyPoker'}),
            ('setMyShortDescription', {'short_description': short}),
            ('setMyDescription', {'description': desc}),
        ]:
            r = await client.post('https://api.telegram.org/bot' + token + '/' + method, json=payload)
            print(method + '=' + ('OK' if r.is_success else 'FAIL'))
asyncio.run(main())
PY

git add app/bot/telegram.py static/branding/mypoker_avatar_512.jpg static/branding/mypoker_avatar_512.png static/branding/mypoker_welcome_1280x960.jpg tests/test_brand_stage16.py
git commit -m 'Add MyPoker branding assets stage 16' || true
git push -u origin main --quiet

ai-deploy-git Phenolemox/poker-bot poker-bot "python -m uvicorn app.main:app --host 10.8.0.1 --port 8140" "Poker Bot API" 8140 /health >/tmp/stage16_deploy.log 2>&1 || { echo DEPLOY_FAIL; tail -60 /tmp/stage16_deploy.log; echo POKER_BRAND_STAGE16_FAIL; exit 1; }
echo "DEPLOY_OK"
tail -18 /tmp/stage16_deploy.log

echo "===== STAGE16 RESULT ====="
git -C /opt/repos/poker-bot log --oneline -3
echo "avatar=/opt/apps/poker-bot/static/branding/mypoker_avatar_512.jpg"
echo "welcome=/opt/apps/poker-bot/static/branding/mypoker_welcome_1280x960.jpg"
echo "health=$(curl -s --max-time 5 http://10.8.0.1:8140/health)"
echo "ready=$(curl -s --max-time 5 http://10.8.0.1:8140/ready)"
echo "sessions=$(curl -s --max-time 5 http://10.8.0.1:8140/ops/sessions)"
ai-sync-check | tail -18
echo "POKER_BRAND_STAGE16_DONE"
