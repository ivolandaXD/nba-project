import os
from urllib.parse import urlparse

import psycopg2
from dotenv import load_dotenv

load_dotenv()


def connect():
    url = os.environ.get("DATABASE_URL")
    if not url:
        raise SystemExit("Defina DATABASE_URL no .env (mesmo banco do Rails).")
    parsed = urlparse(url)
    return psycopg2.connect(
        host=parsed.hostname,
        port=parsed.port or 5432,
        user=parsed.username,
        password=parsed.password,
        dbname=parsed.path.lstrip("/"),
    )
