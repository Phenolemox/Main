import hashlib
import hmac
import time
from urllib.parse import parse_qsl, unquote

MAX_AUTH_AGE_SECONDS = 86400


class AuthError(ValueError):
    pass


def constant_eq(a: str, b: str) -> bool:
    return hmac.compare_digest((a or "").encode(), (b or "").encode())


def validate_webhook_secret(header_value: str | None, expected: str | None) -> bool:
    if not expected:
        return True
    return constant_eq(header_value or "", expected)


def validate_webapp_init_data(init_data: str, bot_token: str, *, max_age_seconds: int = MAX_AUTH_AGE_SECONDS) -> dict[str, str]:
    """Validate Telegram/MAX Mini App initData.

    Telegram and MAX use the same abstract HMAC pattern:
    secret_key = HMAC_SHA256(key='WebAppData', message=bot_token)
    hash = HMAC_SHA256(key=secret_key, message=sorted launch params)
    """
    if not init_data or not bot_token:
        raise AuthError("missing init data or bot token")

    pairs = parse_qsl(init_data, keep_blank_values=True, strict_parsing=False)
    if sum(1 for k, _ in pairs if k == "hash") != 1:
        raise AuthError("bad hash count")

    incoming_hash = next(v for k, v in pairs if k == "hash")
    cleaned: list[tuple[str, str]] = []

    for key, value in pairs:
        if key == "hash":
            continue
        cleaned.append((key, unquote(value)))

    cleaned.sort(key=lambda item: item[0])
    launch_params = "\n".join(f"{k}={v}" for k, v in cleaned)

    secret_key = hmac.new(b"WebAppData", bot_token.encode(), hashlib.sha256).digest()
    calculated = hmac.new(secret_key, launch_params.encode(), hashlib.sha256).hexdigest()

    if not constant_eq(calculated, incoming_hash):
        raise AuthError("bad signature")

    data = dict(cleaned)
    auth_date = data.get("auth_date")

    if auth_date and max_age_seconds > 0:
        try:
            if time.time() - int(auth_date) > max_age_seconds:
                raise AuthError("init data expired")
        except ValueError as exc:
            raise AuthError("bad auth_date") from exc

    return data
