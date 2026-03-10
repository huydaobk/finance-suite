from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone
from typing import Optional, List

import psycopg
from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.security import OAuth2PasswordBearer
from jose import jwt, JWTError
from passlib.hash import bcrypt
from pydantic import BaseModel


def _read_file(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read().strip()


class Settings:
    def __init__(self):
        self.db_host = os.environ.get("FINANCE_DB_HOST", "127.0.0.1")
        self.db_port = int(os.environ.get("FINANCE_DB_PORT", "5432"))
        self.db_name = os.environ.get("FINANCE_DB_NAME", "finance")
        self.db_user = os.environ.get("FINANCE_DB_USER", "finance_user")
        pw_file = os.environ.get("FINANCE_DB_PASSWORD_FILE")
        self.db_password = _read_file(pw_file) if pw_file else os.environ.get("FINANCE_DB_PASSWORD", "")

        secret_file = os.environ.get("JWT_SECRET_FILE")
        self.jwt_secret = _read_file(secret_file) if secret_file else os.environ.get("JWT_SECRET", "change-me")
        self.jwt_alg = os.environ.get("JWT_ALG", "HS256")
        self.jwt_expire_days = int(os.environ.get("JWT_EXPIRE_DAYS", "14"))

        self.admin_username = os.environ.get("ADMIN_USERNAME", "huy")
        self.admin_password_bcrypt = os.environ.get("ADMIN_PASSWORD_BCRYPT", "")
        self.ingest_shared_secret = os.environ.get("INGEST_SHARED_SECRET", "")


settings = Settings()


def db_conn():
    return psycopg.connect(
        host=settings.db_host,
        port=settings.db_port,
        dbname=settings.db_name,
        user=settings.db_user,
        password=settings.db_password,
        autocommit=True,
    )


def create_access_token(sub: str) -> str:
    now = datetime.now(timezone.utc)
    exp = now + timedelta(days=settings.jwt_expire_days)
    payload = {
        "sub": sub,
        "iat": int(now.timestamp()),
        "exp": int(exp.timestamp()),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_alg)


oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login")


def get_current_user(token: str = Depends(oauth2_scheme)) -> str:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_alg])
        sub = payload.get("sub")
        if not sub:
            raise HTTPException(status_code=401, detail="Invalid token")
        return sub
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")


class LoginReq(BaseModel):
    username: str
    password: str


class LoginResp(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in_days: int


class Tx(BaseModel):
    id: int
    created_at: datetime
    type: str
    amount_vnd: int
    category: Optional[str] = None
    wallet: Optional[str] = None
    note: Optional[str] = None
    tx_date: str
    raw_text: str


class SyncResp(BaseModel):
    items: List[Tx]


class AckReq(BaseModel):
    ids: List[int]


class IngestTransactionReq(BaseModel):
    type: str
    amount_vnd: int
    category: Optional[str] = None
    wallet: Optional[str] = None
    note: Optional[str] = None
    tx_date: str
    raw_text: str


app = FastAPI(title="Finance API", version="0.1.0")


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.post("/auth/login", response_model=LoginResp)
def login(req: LoginReq):
    if req.username != settings.admin_username:
        raise HTTPException(status_code=401, detail="Bad credentials")
    if not settings.admin_password_bcrypt:
        raise HTTPException(status_code=500, detail="Admin password not configured")
    if not bcrypt.verify(req.password, settings.admin_password_bcrypt):
        raise HTTPException(status_code=401, detail="Bad credentials")
    token = create_access_token(req.username)
    return LoginResp(access_token=token, expires_in_days=settings.jwt_expire_days)


@app.get("/sync", response_model=SyncResp)
def sync(
    current_user: str = Depends(get_current_user),
    since: Optional[str] = None,
    limit: int = 200,
):
    where = "status = 'new'"
    params = []
    if since:
        where += " AND created_at > %s"
        params.append(since)
    params.append(limit)

    q = f"""
      SELECT id, created_at, type, amount_vnd, category, wallet, note, tx_date::text, raw_text
      FROM transactions_inbox
      WHERE {where}
      ORDER BY created_at ASC
      LIMIT %s
    """

    items: List[Tx] = []
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(q, params)
            for row in cur.fetchall():
                items.append(
                    Tx(
                        id=row[0],
                        created_at=row[1],
                        type=row[2],
                        amount_vnd=row[3],
                        category=row[4],
                        wallet=row[5],
                        note=row[6],
                        tx_date=row[7],
                        raw_text=row[8],
                    )
                )
    return SyncResp(items=items)


@app.post("/sync/ack")
def ack(req: AckReq, current_user: str = Depends(get_current_user)):
    if not req.ids:
        return {"ok": True, "updated": 0}
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE transactions_inbox SET status='synced' WHERE id = ANY(%s)",
                (req.ids,),
            )
            updated = cur.rowcount
    return {"ok": True, "updated": updated}


@app.post("/ingest/transactions")
def ingest_transaction(req: IngestTransactionReq, x_ingest_secret: Optional[str] = Header(default=None)):
    if not settings.ingest_shared_secret:
        raise HTTPException(status_code=500, detail="Ingest secret not configured")
    if x_ingest_secret != settings.ingest_shared_secret:
        raise HTTPException(status_code=401, detail="Bad ingest secret")

    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO transactions_inbox
                  (type, amount_vnd, category, wallet, note, tx_date, raw_text, status)
                VALUES (%s, %s, %s, %s, %s, %s, %s, 'new')
                RETURNING id, created_at, status
                """,
                (
                    req.type,
                    req.amount_vnd,
                    req.category,
                    req.wallet,
                    req.note,
                    req.tx_date,
                    req.raw_text,
                ),
            )
            row = cur.fetchone()
    return {
        "ok": True,
        "id": row[0],
        "created_at": row[1].isoformat() if row and row[1] else None,
        "status": row[2] if row else "new",
    }
