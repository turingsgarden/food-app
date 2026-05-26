"""
In-memory execution trace keyed by request_id (TTL 1 hour).

Each step: {name, status, start_time, end_time, duration_ms, input_summary, output_summary}
"""

from __future__ import annotations

import threading
import time
from contextlib import contextmanager
from contextvars import ContextVar
from typing import Any, Generator

TTL_SECONDS = 3600

_request_id_var: ContextVar[str | None] = ContextVar("food_app_request_id", default=None)
_lock = threading.Lock()
_traces: dict[str, dict[str, Any]] = {}


def _now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _cleanup_expired() -> None:
    cutoff = time.time() - TTL_SECONDS
    expired = [rid for rid, data in _traces.items() if data.get("created_at", 0) < cutoff]
    for rid in expired:
        _traces.pop(rid, None)


def init_trace(request_id: str) -> None:
    with _lock:
        _cleanup_expired()
        _traces[request_id] = {"created_at": time.time(), "steps": []}


def set_request_id(request_id: str | None) -> None:
    _request_id_var.set(request_id)


def get_request_id() -> str | None:
    return _request_id_var.get()


def get_trace_steps(request_id: str) -> list[dict[str, Any]] | None:
    with _lock:
        _cleanup_expired()
        entry = _traces.get(request_id)
        if not entry:
            return None
        return list(entry.get("steps") or [])


def record_step(
    request_id: str,
    *,
    name: str,
    status: str,
    start_time: str,
    end_time: str,
    duration_ms: int,
    input_summary: str = "",
    output_summary: str = "",
) -> None:
    step = {
        "name": name,
        "status": status,
        "start_time": start_time,
        "end_time": end_time,
        "duration_ms": max(0, int(duration_ms)),
    }
    if input_summary:
        step["input_summary"] = input_summary[:2000]
    if output_summary:
        step["output_summary"] = output_summary[:2000]

    with _lock:
        entry = _traces.get(request_id)
        if not entry:
            return
        entry["steps"].append(step)


@contextmanager
def trace_node(
    request_id: str,
    name: str,
    *,
    input_summary: str = "",
) -> Generator[dict[str, Any], None, None]:
    meta: dict[str, Any] = {"output_summary": ""}
    start_ts = _now_iso()
    t0 = time.perf_counter()
    status = "ok"
    try:
        yield meta
    except Exception:
        status = "error"
        raise
    finally:
        end_ts = _now_iso()
        record_step(
            request_id,
            name=name,
            status=status,
            start_time=start_ts,
            end_time=end_ts,
            duration_ms=int((time.perf_counter() - t0) * 1000),
            input_summary=input_summary,
            output_summary=str(meta.get("output_summary") or ""),
        )
