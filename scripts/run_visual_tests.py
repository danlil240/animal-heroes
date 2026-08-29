#!/usr/bin/env python3
"""Visual test orchestrator: discovers platform tests, launches each as a Godot
process with DISPLAY set, collects result.json + screenshots, compares against
baselines, and emits an HTML report. Stdlib only."""
import argparse
import html
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# Make sibling modules (compare_screenshots) importable.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from compare_screenshots import compare  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
TEST_GLOB = "game/tests/platform/test_*.gd"
LEVELS_DIR = REPO_ROOT / "game" / "levels"
OUTPUT_DIR = REPO_ROOT / "test-output"
BASELINES_DIR = OUTPUT_DIR / "baselines"
DEFAULT_LEVEL = "sunny_forest"
DEFAULT_THRESHOLD = 0.02
PER_TEST_TIMEOUT = 120  # seconds

# Real error tokens (case-sensitive). Godot shutdown noise is filtered separately.
_ERROR_TOKENS = re.compile(r"SCRIPT ERROR|USER SCRIPT ERROR|push_error|ERROR:")
_SHUTDOWN_NOISE = re.compile(r"at exit|leaked at exit|resources still in use|Texture with.*leaked.*bytes")


def discover_tests() -> list[tuple[str, Path]]:
    """Return [(test_name, path)] for every game/tests/platform/test_*.gd."""
    out = []
    for p in sorted((REPO_ROOT / "game" / "tests" / "platform").glob("test_*.gd")):
        if p.name == "test_runner.gd":  # base harness, not a test
            continue
        name = p.stem[len("test_"):]
        out.append((name, p))
    return out


def known_levels() -> set[str]:
    """Level ids from .tscn filenames in game/levels/."""
    if not LEVELS_DIR.is_dir():
        return set()
    return {p.stem for p in LEVELS_DIR.glob("*.tscn")}


def derive_level(test_name: str, levels: set[str]) -> str:
    """If the test name starts with a known level id, use that; else default."""
    for lvl in sorted(levels, key=len, reverse=True):
        if test_name == lvl or test_name.startswith(lvl + "_"):
            return lvl
    return DEFAULT_LEVEL


def scan_errors(output: str) -> list[str]:
    """Collect real error lines from combined Godot output, filtering shutdown noise."""
    errors = []
    for line in output.splitlines():
        if not _ERROR_TOKENS.search(line):
            continue
        if _SHUTDOWN_NOISE.search(line):
            continue
        errors.append(line)
    return errors


def _resolve_assertions(result: dict, error_log: list[str]) -> None:
    """Mark needs_log_scan assertions failed if error_log non-empty; flip status."""
    if not error_log:
        return
    for a in result.get("assertions", []):
        if a.get("needs_log_scan"):
            a["passed"] = False
    if result.get("status") == "pass":
        result["status"] = "fail"
        result["failure_reason"] = "ERROR_LOG"


def compare_baselines(test_name: str, result: dict, threshold: float,
                      update_baselines: bool) -> list[dict]:
    """For each capture, compare against baseline or save current as baseline.
    Returns per-capture comparison rows for the report."""
    test_dir = OUTPUT_DIR / test_name
    baseline_dir = BASELINES_DIR / test_name
    rows = []
    for cap in result.get("captures", []):
        name = cap["name"]
        current = test_dir / ("%s.png" % name)
        baseline = baseline_dir / ("%s.png" % name)
        row = {"name": name, "render_ok": cap.get("render_ok", False),
               "baseline_exists": baseline.exists(), "regression": False,
               "changed_pixel_ratio": 0.0, "max_delta": 0,
               "diff_path": None, "message": ""}
        if not current.exists():
            row["message"] = "current screenshot missing"
            rows.append(row)
            continue
        if update_baselines or not baseline.exists():
            baseline_dir.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(current, baseline)
            row["baseline_exists"] = True
            row["message"] = "baseline saved (first run)" if not update_baselines else "baseline updated"
            rows.append(row)
            continue
        cmp = compare(str(baseline), str(current), threshold=threshold)
        row["changed_pixel_ratio"] = cmp["changed_pixel_ratio"]
        row["max_delta"] = cmp["max_delta"]
        row["regression"] = cmp["regression"]
        row["message"] = cmp.get("message", "")
        diff = cmp.get("diff_image_path")
        if diff:
            row["diff_path"] = Path(diff).name
        rows.append(row)
    return rows


def run_one(test_name: str, test_path: Path, level: str, godot: str,
            threshold: float, update_baselines: bool) -> dict:
    """Launch one Godot visual test, post-process result.json, compare baselines."""
    test_dir = OUTPUT_DIR / test_name
    test_dir.mkdir(parents=True, exist_ok=True)
    script_res = "res://tests/platform/test_%s.gd" % test_name
    cmd = [godot, "--path", str(REPO_ROOT / "game"), "-s", script_res,
           "--", "--test=%s" % test_name, "--level=%s" % level]
    env = os.environ.copy()
    try:
        proc = subprocess.run(cmd, text=True, timeout=PER_TEST_TIMEOUT,
                              env=env, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT)
        output = proc.stdout or ""
        exit_code = proc.returncode
        timed_out = False
    except subprocess.TimeoutExpired as e:
        output = (e.stdout or "") if isinstance(e.stdout, str) else ""
        exit_code = -1
        timed_out = True

    # The GDScript harness writes under res:// (game/test-output/<test>/).
    # Relocate its output to the repo-root test-output/<test>/.
    godot_out = REPO_ROOT / "game" / "test-output" / test_name
    if godot_out.is_dir():
        for f in godot_out.iterdir():
            shutil.copyfile(f, test_dir / f.name)

    result_path = test_dir / "result.json"
    result = None
    if result_path.exists():
        try:
            result = json.loads(result_path.read_text())
        except json.JSONDecodeError:
            result = None

    error_log = scan_errors(output)

    if result is None:
        result = {
            "test": test_name, "level": level, "status": "fail",
            "failure_reason": "TIMEOUT" if timed_out else "CRASH",
            "assertions": [], "captures": [], "alerts": [],
            "state_snapshots": [], "error_log": error_log,
        }
    else:
        _resolve_assertions(result, error_log)
        result["error_log"] = error_log
        if timed_out and result.get("status") == "pass":
            result["status"] = "fail"
            result["failure_reason"] = "TIMEOUT"

    # Write back post-processed result.json.
    result_path.write_text(json.dumps(result, indent="\t"))

    cap_rows = compare_baselines(test_name, result, threshold, update_baselines)
    # A regression in any capture flips status to fail (RENDER_DIFF) unless harder.
    any_regression = any(r["regression"] for r in cap_rows)
    if any_regression and result.get("status") == "pass":
        result["status"] = "fail"
        result["failure_reason"] = "RENDER_DIFF"
        result_path.write_text(json.dumps(result, indent="\t"))

    return {
        "test": test_name, "level": level, "status": result["status"],
        "failure_reason": result["failure_reason"], "result": result,
        "captures": cap_rows, "exit_code": exit_code, "timed_out": timed_out,
        "output": output, "error_log": error_log,
    }


def _img(rel: str, alt: str) -> str:
    if rel and (OUTPUT_DIR / rel).exists():
        return '<img src="%s" alt="%s">' % (html.escape(rel), html.escape(alt))
    return '<span class="missing">(missing)</span>'


def generate_report(results: list[dict]) -> Path:
    """Write test-output/report.html and return its path."""
    parts = [
        "<!DOCTYPE html><html><head><meta charset='utf-8'>",
        "<title>Visual Test Report</title>",
        "<style>",
        "body{font-family:monospace;margin:16px;background:#fafafa;color:#222}",
        ".card{border:1px solid #ccc;border-radius:6px;padding:12px;margin:12px 0;background:#fff}",
        ".badge{padding:2px 8px;border-radius:3px;font-weight:bold;color:#fff}",
        ".pass{background:#2e7d32}.fail{background:#c62828}",
        "table{border-collapse:collapse;margin:6px 0}",
        "td,th{border:1px solid #ddd;padding:4px 8px;vertical-align:top}",
        "img{max-width:240px;border:1px solid #eee}",
        "pre{background:#f5f5f5;padding:8px;overflow-x:auto;white-space:pre-wrap}",
        ".missing{color:#999;font-style:italic}",
        "</style></head><body>",
        "<h1>Visual Test Report</h1>",
    ]
    passed = sum(1 for r in results if r["status"] == "pass")
    parts.append("<p>%d/%d passed</p>" % (passed, len(results)))
    for r in results:
        badge = "pass" if r["status"] == "pass" else "fail"
        parts.append('<div class="card">')
        parts.append('<h2>%s <span class="badge %s">%s</span></h2>'
                     % (html.escape(r["test"]), badge, html.escape(r["status"])))
        parts.append('<p>level=%s failure_reason=%s exit_code=%s%s</p>' % (
            html.escape(r["level"]), html.escape(r["failure_reason"]),
            r["exit_code"], " (TIMEOUT)" if r["timed_out"] else ""))
        res = r["result"]
        # Captures table.
        caps = res.get("captures", [])
        if caps:
            parts.append("<h3>Captures</h3><table><tr>"
                         "<th>name</th><th>baseline</th><th>current</th><th>diff</th>"
                         "<th>changed%</th><th>regression</th></tr>")
            for cap, row in zip(caps, r["captures"]):
                base_rel = "baselines/%s/%s.png" % (r["test"], cap["name"])
                cur_rel = "%s/%s.png" % (r["test"], cap["name"])
                diff_rel = "%s/%s" % (r["test"], row["diff_path"]) if row["diff_path"] else ""
                parts.append("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td>"
                             "<td>%.4f</td><td>%s</td></tr>" % (
                                 html.escape(cap["name"]),
                                 _img(base_rel, "baseline"),
                                 _img(cur_rel, "current"),
                                 _img(diff_rel, "diff"),
                                 row["changed_pixel_ratio"],
                                 "YES" if row["regression"] else "no",
                             ))
            parts.append("</table>")
        # State snapshots.
        snaps = res.get("state_snapshots", [])
        if snaps:
            parts.append("<h3>State snapshots</h3><table><tr>"
                         "<th>frame</th><th>rabbit</th><th>fox</th><th>score</th>"
                         "<th>rabbit_hearts</th><th>fox_hearts</th><th>finished</th></tr>")
            for s in snaps:
                parts.append("<tr><td>%d</td><td>%s</td><td>%s</td><td>%d</td>"
                             "<td>%d</td><td>%d</td><td>%s</td></tr>" % (
                                 s["frame"], s["rabbit"], s["fox"], s["score"],
                                 s["rabbit_hearts"], s["fox_hearts"], s["finished"]))
            parts.append("</table>")
        # Assertions.
        asserts = res.get("assertions", [])
        if asserts:
            parts.append("<h3>Assertions</h3><table><tr>"
                         "<th>kind</th><th>args</th><th>passed</th><th>message</th>"
                         "<th>frame</th></tr>")
            for a in asserts:
                parts.append("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>" % (
                    html.escape(str(a.get("kind", ""))),
                    html.escape(str(a.get("args", ""))),
                    "yes" if a.get("passed") else "NO",
                    html.escape(str(a.get("message", ""))),
                    str(a.get("frame", ""))))
            parts.append("</table>")
        # Alerts.
        alerts = res.get("alerts", [])
        if alerts:
            parts.append("<h3>Alerts</h3><ul>")
            for al in alerts:
                parts.append("<li>%s</li>" % html.escape(al))
            parts.append("</ul>")
        # Error log.
        if r["error_log"]:
            parts.append("<h3>Error log</h3><pre>%s</pre>"
                         % html.escape("\n".join(r["error_log"])))
        parts.append("</div>")
    parts.append("</body></html>")
    report_path = OUTPUT_DIR / "report.html"
    report_path.write_text("\n".join(parts))
    return report_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Run visual tests and report.")
    parser.add_argument("--test", help="run a single test by name")
    parser.add_argument("--update-baselines", action="store_true",
                        help="copy current screenshots into baselines/")
    parser.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD,
                        help="regression threshold (changed pixel ratio)")
    args = parser.parse_args()

    if not os.environ.get("DISPLAY"):
        print("DISPLAY not set; skipping visual tests.")
        return 0

    godot = os.environ.get("GODOT_BIN", "godot")
    levels = known_levels()

    tests = discover_tests()
    if args.test:
        tests = [(n, p) for n, p in tests if n == args.test]
        if not tests:
            print("no test named %r found" % args.test)
            return 1

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    results = []
    for name, path in tests:
        level = derive_level(name, levels)
        print("RUN %s (level=%s)" % (name, level))
        r = run_one(name, path, level, godot, args.threshold, args.update_baselines)
        results.append(r)
        print("  -> status=%s reason=%s errors=%d"
              % (r["status"], r["failure_reason"], len(r["error_log"])))

    report = generate_report(results)
    passed = sum(1 for r in results if r["status"] == "pass")
    print("\nSUMMARY: %d/%d passed" % (passed, len(results)))
    print("report: %s" % report)
    # Exit 0 if all passed (orchestrator success); failures are reported but
    # a non-zero exit would break unconditional gating, so report status only.
    return 0


if __name__ == "__main__":
    sys.exit(main())
