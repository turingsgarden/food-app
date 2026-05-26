from __future__ import annotations

from flask import Blueprint


def make_blueprint(name: str) -> Blueprint:
    return Blueprint(name, __name__)

