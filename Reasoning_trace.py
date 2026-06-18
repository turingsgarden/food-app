"""
reasoning_trace.py

Each reasoning entry follows the OCED pattern:
    Observe   → what data/state was seen
    Consider  → what options or checks were evaluated
    Evaluate  → the outcome of each check (PASS / FAIL / WARN + detail)
    Decide    → the final choice and justification
    Confidence → how certain the agent is (high / medium / low + reason)
    Risks      → any known caveats or failure modes

Usage
-----
Minimal (decide only):
    from reasoning_trace import build_reasoning
    meta["output_summary"] = build_reasoning(decide="Image valid — proceed")

Full:
    meta["output_summary"] = build_reasoning(
        observe={"dish": dish, "calories": calories},
        consider=["Is visible_count >= 2?", "Are calories > 0?"],
        evaluate={"calories_check": "PASS — 450 kcal", "dish_check": "PASS"},
        decide="Output VALID — passing to caller",
        confidence="high",
        risks="None",
    )

Standalone (writes directly into execution_trace without trace_node):
    from reasoning_trace import record_reasoning
    record_reasoning(
        request_id=rid,
        node_name="validate_output",
        decide="Output VALID",
        confidence="high",
    )

"""

from __future__ import annotations

import json
import time
from typing import Any

from execution_trace import record_step


# ---------------------------------------------------------------------------
# Core builder
# ---------------------------------------------------------------------------

def build_reasoning(
    *,
    observe: dict[str, Any] | str | None = None,
    consider: list[str] | None = None,
    evaluate: dict[str, str] | None = None,
    decide: str,
    confidence: str = "medium",
    risks: str = "None",
) -> str:
    """
    Build a structured reasoning dict and return it as a JSON string.

    This string is designed to be assigned to meta["output_summary"] inside
    a trace_node block so it is captured by your existing execution_trace.

    Parameters
    ----------
    observe     : What the node saw — pass a dict of key state values, or a plain string.
    consider    : List of questions / options the node evaluated.
    evaluate    : Dict of check_name → result string (e.g. "PASS — 450 kcal").
    decide      : The decision made and why. Required.
    confidence  : "high" | "medium" | "low" — optionally append a reason after a dash.
    risks       : Known caveats, edge cases, or failure modes.

    Returns
    -------
    JSON string ready to assign to meta["output_summary"].
    """
    reasoning: dict[str, Any] = {}

    if observe is not None:
        reasoning["observe"] = observe

    if consider:
        reasoning["consider"] = consider

    if evaluate:
        reasoning["evaluate"] = evaluate

    reasoning["decide"] = decide
    reasoning["confidence"] = confidence

    if risks and risks.lower() != "none":
        reasoning["risks"] = risks

    return json.dumps(reasoning, ensure_ascii=False)


# ---------------------------------------------------------------------------
# Standalone recorder (use when you are NOT inside a trace_node block)
# ---------------------------------------------------------------------------

def record_reasoning(
    request_id: str,
    node_name: str,
    *,
    observe: dict[str, Any] | str | None = None,
    consider: list[str] | None = None,
    evaluate: dict[str, str] | None = None,
    decide: str,
    confidence: str = "medium",
    risks: str = "None",
    input_summary: str = "",
    status: str = "ok",
) -> None:
    """
    Build a reasoning entry and write it directly into execution_trace.

    Use this when you are NOT inside a trace_node block and want to record
    reasoning as a standalone step.

    Parameters
    ----------
    request_id   : The active request ID (from state["request_id"]).
    node_name    : Name of the node, e.g. "validate_output.reasoning".
    observe      : What the node saw.
    consider     : Options or checks considered.
    evaluate     : Outcomes of each check.
    decide       : The decision and justification. Required.
    confidence   : "high" | "medium" | "low".
    risks        : Known caveats.
    input_summary: Optional short description of inputs for the step record.
    status       : "ok" or "error".
    """
    output = build_reasoning(
        observe=observe,
        consider=consider,
        evaluate=evaluate,
        decide=decide,
        confidence=confidence,
        risks=risks,
    )

    now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    record_step(
        request_id,
        name=f"{node_name}.reasoning",
        status=status,
        start_time=now_iso,
        end_time=now_iso,
        duration_ms=0,
        input_summary=input_summary,
        output_summary=output,
    )


# ---------------------------------------------------------------------------
# Convenience helpers for common evaluate patterns
# ---------------------------------------------------------------------------

def check(condition: bool, label: str, *, pass_detail: str = "", fail_detail: str = "") -> str:
    """
    Return a standard PASS / FAIL evaluation string.

    Example
    -------
    evaluate={
        "calories_check": check(calories > 0, "calories > 0", fail_detail=f"got {calories}"),
        "dish_check":     check(bool(dish),   "dish name present"),
    }
    """
    if condition:
        result = "PASS"
        if pass_detail:
            result += f" — {pass_detail}"
    else:
        result = "FAIL"
        if fail_detail:
            result += f" — {fail_detail}"
    return result


def warn(condition: bool, label: str, *, detail: str = "") -> str:
    """
    Return a PASS or WARN evaluation string (no hard failure).

    Example
    -------
    evaluate={
        "visible_count": warn(visible_count >= 3, ">=3 ingredients", detail=f"only {visible_count}"),
    }
    """
    if condition:
        return "PASS"
    result = "WARN"
    if detail:
        result += f" — {detail}"
    return result
