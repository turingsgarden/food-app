"""
Langfuse client and helpers for tracing Gemini calls and LangGraph nodes.

If LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY are not set, all helpers no-op safely.
"""

from __future__ import annotations

import logging
import os
import time
from contextlib import contextmanager
from contextvars import ContextVar
from typing import Any, Callable, Optional, TypeVar, cast

logger = logging.getLogger(__name__)

GEMINI_MODEL_NAME = "gemini-2.5-flash"

_langfuse_client: Any | None = None
_trace_id_var: ContextVar[Optional[str]] = ContextVar("langfuse_trace_id", default=None)

R = TypeVar("R")


def get_langfuse_client() -> Any | None:
    global _langfuse_client

    if _langfuse_client is not None:
        return _langfuse_client

    pk = os.getenv("LANGFUSE_PUBLIC_KEY", "").strip()
    sk = os.getenv("LANGFUSE_SECRET_KEY", "").strip()
    if not pk or not sk:
        logger.debug("Langfuse keys not found in environment, skipping tracing")
        return None

    host = (os.getenv("LANGFUSE_HOST") or "https://cloud.langfuse.com").strip()
    try:
        from langfuse import Langfuse

        _langfuse_client = Langfuse(public_key=pk, secret_key=sk, host=host)
        logger.info("Langfuse client initialized successfully (host=%s)", host)
    except Exception as exc:
        logger.warning("Langfuse init failed: %s", exc)
        return None

    return _langfuse_client


def flush_langfuse() -> None:
    lf = get_langfuse_client()
    if lf:
        try:
            lf.flush()
        except Exception:
            pass


def set_active_trace_id(trace_id: str) -> None:
    _trace_id_var.set(trace_id)


def clear_active_trace_id() -> None:
    _trace_id_var.set(None)


def get_active_trace_context() -> Optional[dict[str, str]]:
    tid = _trace_id_var.get()
    if not tid:
        return None
    return {"trace_id": tid}


def redact_for_trace(obj: Any) -> Any:
    if isinstance(obj, dict):
        out: dict[str, Any] = {}
        for k, v in obj.items():
            if k in ("image_base64", "image_data") and isinstance(v, str) and len(v) > 200:
                out[k] = f"<redacted base64 len={len(v)}>"
            else:
                out[k] = redact_for_trace(v)
        return out
    if isinstance(obj, list) and len(obj) > 50:
        return [redact_for_trace(x) for x in obj[:50]] + ["<truncated>"]
    return obj


def _response_text_preview(response: Any, max_len: int = 12000) -> str:
    try:
        t = (getattr(response, "text", None) or "").strip()
        if t:
            return t[:max_len]
    except (ValueError, AttributeError):
        pass
    parts: list[str] = []
    for cand in getattr(response, "candidates", None) or []:
        content = getattr(cand, "content", None)
        if not content:
            continue
        for part in getattr(content, "parts", None) or []:
            tx = getattr(part, "text", None)
            if tx:
                parts.append(str(tx))
    s = "".join(parts).strip()
    return s[:max_len] if s else "<empty>"


def gemini_usage_details(response: Any) -> Optional[dict[str, int]]:
    um = getattr(response, "usage_metadata", None)
    if um is None:
        return None
    details: dict[str, int] = {}
    mapping = (
        ("prompt_token_count", "input"),
        ("candidates_token_count", "output"),
        ("total_token_count", "total"),
    )
    for attr, key in mapping:
        if hasattr(um, attr):
            try:
                details[key] = int(getattr(um, attr) or 0)
            except (TypeError, ValueError):
                continue
    return details if details else None


def tokens_from_response(response: Any) -> int:
    usage = gemini_usage_details(response)
    if not usage:
        return 0
    total = int(usage.get("total") or 0)
    if total > 0:
        return total
    return int(usage.get("input") or 0) + int(usage.get("output") or 0)


@contextmanager
def lf_trace(name: str, input_payload: Any = None):
    lf = get_langfuse_client()
    tc = get_active_trace_context()
    if not lf or not tc:
        yield None
        return
    from langfuse.types import TraceContext

    with lf.start_as_current_observation(
        as_type="chain",
        name=name,
        trace_context=cast(TraceContext, tc),
        input=redact_for_trace(input_payload),
    ) as root:
        yield root


@contextmanager
def lf_node_span(name: str, input_payload: Any = None):
    lf = get_langfuse_client()
    tc = get_active_trace_context()
    if not lf or not tc:
        yield None
        return
    from langfuse.types import TraceContext

    with lf.start_as_current_observation(
        as_type="span",
        name=name,
        trace_context=cast(TraceContext, tc),
        input=redact_for_trace(input_payload),
    ) as span:
        yield span


lf_span = lf_node_span


def lf_generation(
    name: str,
    input_payload: Any,
    thunk: Callable[[], R],
    model: str | None = None,
) -> R:
    lf = get_langfuse_client()
    tc = get_active_trace_context()
    if not lf or not tc:
        return thunk()
    from langfuse.types import TraceContext

    model_name = model or GEMINI_MODEL_NAME
    t0 = time.perf_counter()
    with lf.start_as_current_observation(
        as_type="generation",
        name=name,
        trace_context=cast(TraceContext, tc),
        model=model_name,
        input=redact_for_trace(input_payload),
    ) as gen:
        response = thunk()
        latency_ms = int((time.perf_counter() - t0) * 1000)
        usage = gemini_usage_details(response)
        preview = _response_text_preview(response)
        kwargs: dict[str, Any] = {"output": preview, "metadata": {"latency_ms": latency_ms}}
        if usage:
            kwargs["usage_details"] = usage
        gen.update(**kwargs)
    return response
