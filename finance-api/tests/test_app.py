from __future__ import annotations

import importlib
import os
import sys
from pathlib import Path

import bcrypt
from fastapi.testclient import TestClient


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def _load_app_module(*, admin_password: str = "secret123"):
    os.environ["ADMIN_USERNAME"] = "huy"
    os.environ["ADMIN_PASSWORD_BCRYPT"] = bcrypt.hashpw(
        admin_password.encode("utf-8"),
        bcrypt.gensalt(),
    ).decode("utf-8")
    os.environ["JWT_SECRET"] = "test-secret"
    os.environ["JWT_EXPIRE_DAYS"] = "14"

    sys.modules.pop("finance_api.app", None)
    return importlib.import_module("finance_api.app")


def test_healthz_ok():
    app_module = _load_app_module()
    client = TestClient(app_module.app)

    response = client.get("/healthz")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_login_success_returns_bearer_token():
    app_module = _load_app_module()
    client = TestClient(app_module.app)

    response = client.post(
        "/auth/login",
        json={"username": "huy", "password": "secret123"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["token_type"] == "bearer"
    assert body["expires_in_days"] == 14
    assert isinstance(body["access_token"], str)
    assert body["access_token"]


def test_login_fail_with_bad_password():
    app_module = _load_app_module()
    client = TestClient(app_module.app)

    response = client.post(
        "/auth/login",
        json={"username": "huy", "password": "wrong-password"},
    )

    assert response.status_code == 401
    assert response.json()["detail"] == "Bad credentials"
