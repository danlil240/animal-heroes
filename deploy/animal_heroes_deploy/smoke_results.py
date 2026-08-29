"""Parse dual-tablet smoke evidence into structured performance metrics.

Reads the before/after dumpsys and logcat captures produced by
scripts/device_smoke.sh and computes the metrics table required by
docs/test-results/sm-t220-performance.md.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field, asdict
from pathlib import Path


@dataclass(frozen=True)
class DeviceSnapshot:
    """Parsed metrics from a single before or after capture."""

    total_frames: int | None = None
    percentile_99_ms: float | None = None
    percentile_95_ms: float | None = None
    percentile_90_ms: float | None = None
    percentile_50_ms: float | None = None
    janky_frames: int | None = None
    janky_percent: float | None = None
    total_pss_kb: int | None = None
    battery_level: int | None = None
    thermal_status: int | None = None
    crash_count: int = 0
    reconnect_count: int = 0


@dataclass
class DeviceMetrics:
    """Computed metrics for one device across a before/after interval."""

    role: str
    average_fps: float | None = None
    percentile_99_ms: float | None = None
    percentile_95_ms: float | None = None
    peak_pss_mb: float | None = None
    thermal_status: int | None = None
    battery_change: int | None = None
    crash_count: int = 0
    reconnect_count: int = 0
    errors: list[str] = field(default_factory=list)


_FRAME_RE = re.compile(r"Total frames rendered:\s*(\d+)")
_JANKY_RE = re.compile(r"Janky frames:\s*(\d+)\s*\(([\d.]+)%\)")
_PCT_RE = re.compile(r"(\d+)(?:st|nd|rd|th)\s+percentile:\s*([\d.]+)ms")
_PSS_RE = re.compile(r"TOTAL PSS:\s*(\d+)", re.IGNORECASE)
_PSS_FALLBACK_RE = re.compile(r"^\s*TOTAL\s+(\d+)", re.IGNORECASE | re.MULTILINE)
_BATTERY_RE = re.compile(r"^\s*level:\s*(\d+)", re.MULTILINE)
_THERMAL_RE = re.compile(r"(?:CurrentThermalStatus|ThermalEventStatus|status):\s*(\d+)")
_CRASH_RE = re.compile(r"FATAL EXCEPTION|AndroidRuntime.*FATAL|tombstone|signal\s+\d+", re.IGNORECASE)
_RECONNECT_RE = re.compile(r"reconnect", re.IGNORECASE)


class ParseError(ValueError):
    """Raised when evidence files cannot be parsed."""


def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        raise ParseError(f"cannot read {path}: {exc}") from exc


def parse_gfxinfo(text: str) -> dict:
    fields: dict = {}
    m = _FRAME_RE.search(text)
    if m:
        fields["total_frames"] = int(m.group(1))
    m = _JANKY_RE.search(text)
    if m:
        fields["janky_frames"] = int(m.group(1))
        fields["janky_percent"] = float(m.group(2))
    for m in _PCT_RE.finditer(text):
        pct = int(m.group(1))
        ms = float(m.group(2))
        if pct == 50:
            fields["percentile_50_ms"] = ms
        elif pct == 90:
            fields["percentile_90_ms"] = ms
        elif pct == 95:
            fields["percentile_95_ms"] = ms
        elif pct == 99:
            fields["percentile_99_ms"] = ms
    return fields


def parse_meminfo(text: str) -> dict:
    m = _PSS_RE.search(text)
    if m is None:
        m = _PSS_FALLBACK_RE.search(text)
    if m:
        return {"total_pss_kb": int(m.group(1))}
    return {}


def parse_battery(text: str) -> dict:
    m = _BATTERY_RE.search(text)
    if m:
        return {"battery_level": int(m.group(1))}
    return {}


def parse_thermalservice(text: str) -> dict:
    m = _THERMAL_RE.search(text)
    if m:
        return {"thermal_status": int(m.group(1))}
    return {}


def parse_logcat(text: str) -> dict:
    crash_count = len(_CRASH_RE.findall(text))
    reconnect_count = len(_RECONNECT_RE.findall(text))
    return {"crash_count": crash_count, "reconnect_count": reconnect_count}


def parse_snapshot(results_dir: Path, role: str, timing: str) -> DeviceSnapshot:
    prefix = results_dir / f"{role}-{timing}"
    fields: dict = {}
    gfx_path = Path(f"{prefix}-gfxinfo.txt")
    mem_path = Path(f"{prefix}-meminfo.txt")
    batt_path = Path(f"{prefix}-battery.txt")
    therm_path = Path(f"{prefix}-thermalservice.txt")
    log_path = Path(f"{prefix}-logcat.txt")

    if gfx_path.exists():
        fields.update(parse_gfxinfo(_read(gfx_path)))
    if mem_path.exists():
        fields.update(parse_meminfo(_read(mem_path)))
    if batt_path.exists():
        fields.update(parse_battery(_read(batt_path)))
    if therm_path.exists():
        fields.update(parse_thermalservice(_read(therm_path)))
    if log_path.exists():
        fields.update(parse_logcat(_read(log_path)))
    return DeviceSnapshot(**fields)


def compute_metrics(
    role: str, before: DeviceSnapshot, after: DeviceSnapshot, duration_seconds: int
) -> DeviceMetrics:
    metrics = DeviceMetrics(role=role)
    errors: list[str] = []

    if before.total_frames is not None and after.total_frames is not None:
        frame_delta = after.total_frames - before.total_frames
        if duration_seconds > 0:
            metrics.average_fps = round(frame_delta / duration_seconds, 1)
        elif frame_delta < 0:
            errors.append("after frame count is lower than before (gfxinfo may have been reset)")
    elif after.total_frames is not None and duration_seconds > 0:
        errors.append("before gfxinfo missing — average FPS cannot be computed from delta")

    metrics.percentile_99_ms = after.percentile_99_ms
    metrics.percentile_95_ms = after.percentile_95_ms

    if after.total_pss_kb is not None:
        metrics.peak_pss_mb = round(after.total_pss_kb / 1024.0, 1)

    metrics.thermal_status = after.thermal_status
    if after.thermal_status is not None and after.thermal_status >= 3:
        errors.append(f"thermal throttling active (status={after.thermal_status})")

    if before.battery_level is not None and after.battery_level is not None:
        metrics.battery_change = after.battery_level - before.battery_level

    metrics.crash_count = after.crash_count - before.crash_count
    if metrics.crash_count < 0:
        metrics.crash_count = after.crash_count
    if metrics.crash_count > 0:
        errors.append(f"{metrics.crash_count} crash(es) detected in logcat")

    metrics.reconnect_count = after.reconnect_count - before.reconnect_count
    if metrics.reconnect_count < 0:
        metrics.reconnect_count = after.reconnect_count

    metrics.errors = errors
    return metrics


def parse_results(results_dir: Path, duration_seconds: int) -> dict:
    if duration_seconds < 0:
        raise ParseError("duration_seconds must be non-negative")
    roles = []
    for entry in sorted(results_dir.iterdir()):
        m = re.match(r"^(host|client)-before-", entry.name)
        if m and m.group(1) not in roles:
            roles.append(m.group(1))
    if not roles:
        raise ParseError(f"no before/after evidence found in {results_dir}")

    devices = {}
    for role in roles:
        before = parse_snapshot(results_dir, role, "before")
        after = parse_snapshot(results_dir, role, "after")
        devices[role] = asdict(
            compute_metrics(role, before, after, duration_seconds)
        )
    return {
        "duration_seconds": duration_seconds,
        "results_dir": str(results_dir),
        "devices": devices,
    }


def _format_table(report: dict) -> str:
    lines = [
        "| Metric | Host | Client |",
        "| --- | --- | --- |",
    ]
    devices = report["devices"]
    host = devices.get("host", {})
    client = devices.get("client", {})

    def cell(d: dict, key: str, suffix: str = "") -> str:
        v = d.get(key)
        if v is None:
            return "PENDING"
        return f"{v}{suffix}"

    rows = [
        ("Average FPS", "average_fps", ""),
        ("99th percentile frame time", "percentile_99_ms", " ms"),
        ("95th percentile frame time", "percentile_95_ms", " ms"),
        ("Peak memory (MB)", "peak_pss_mb", ""),
        ("Thermal status", "thermal_status", ""),
        ("Battery change (%)", "battery_change", ""),
        ("Reconnect count", "reconnect_count", ""),
        ("Crash count", "crash_count", ""),
    ]
    for label, key, suffix in rows:
        lines.append(f"| {label} | {cell(host, key, suffix)} | {cell(client, key, suffix)} |")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Parse dual-tablet smoke evidence into performance metrics."
    )
    parser.add_argument(
        "results_dir",
        nargs="?",
        default="docs/test-results",
        help="Directory with before/after evidence (default: docs/test-results)",
    )
    parser.add_argument(
        "--duration",
        type=int,
        default=None,
        help="Smoke duration in seconds (default: read from run-duration-seconds.txt)",
    )
    parser.add_argument(
        "--format",
        choices=["json", "table"],
        default="table",
        help="Output format (default: table)",
    )
    args = parser.parse_args(argv)

    results_dir = Path(args.results_dir)
    if not results_dir.is_dir():
        print(f"results directory not found: {results_dir}", file=sys.stderr)
        return 2

    if args.duration is not None:
        duration = args.duration
    else:
        dur_file = results_dir / "run-duration-seconds.txt"
        if not dur_file.exists():
            print(f"duration file not found: {dur_file}", file=sys.stderr)
            return 2
        try:
            duration = int(dur_file.read_text().strip())
        except ValueError:
            print(f"invalid duration in {dur_file}", file=sys.stderr)
            return 2

    try:
        report = parse_results(results_dir, duration)
    except ParseError as exc:
        print(f"parse error: {exc}", file=sys.stderr)
        return 1

    if args.format == "json":
        print(json.dumps(report, indent=2))
    else:
        print(_format_table(report))
        all_errors = []
        for role, dev in report["devices"].items():
            for err in dev.get("errors", []):
                all_errors.append(f"{role}: {err}")
        if all_errors:
            print("\nIssues:")
            for e in all_errors:
                print(f"  - {e}")

    has_failures = any(
        dev.get("crash_count", 0) > 0
        or (dev.get("thermal_status") is not None and dev.get("thermal_status", 0) >= 3)
        for dev in report["devices"].values()
    )
    return 1 if has_failures else 0


if __name__ == "__main__":
    sys.exit(main())
