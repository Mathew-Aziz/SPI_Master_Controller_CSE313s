#!/usr/bin/env python3
"""
run_parallel.py – Parallel regression runner for the SPI Master Verification Project.

Runs every (test, seed) combination using Questa (vsim), with up to MAX_WORKERS
jobs running simultaneously.  Logs are saved to build/ and a summary table is
printed at the end.

Usage examples
--------------
# Use seeds 1-8 (matching Makefile default) with 10 parallel workers:
    python run_parallel.py

# Custom seeds and worker count:
    python run_parallel.py --seeds 1 2 3 42 99 --workers 6

# Run only specific tests:
    python run_parallel.py --tests sanity_test fifo_stress_test --seeds 1 2 3

# Compile first, then run (default behaviour):
    python run_parallel.py --compile
"""

import argparse
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

# ---------------------------------------------------------------------------
# Defaults (mirror the Makefile)
# ---------------------------------------------------------------------------
DEFAULT_SEEDS = list(range(1, 11))          # seeds 1-10
MAX_WORKERS   = 10                           # 10 parallel jobs
BUILD_DIR     = Path("build")

ALL_TESTS = [
    "sanity_test",
    "reg_access_test",
    "mode_coverage_test",
    "width_coverage_test",
    "fifo_stress_test",
    "interrupt_test",
    "clk_div_corner_test",
    "loopback_test",
    "delay_transfer_test",
    "error_injection_test",
    "randomized_sanity_test",
]

# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------
@dataclass
class Job:
    test: str
    seed: int
    log: Path = field(init=False)

    def __post_init__(self):
        self.log = BUILD_DIR / f"log_{self.test}_{self.seed}.log"

@dataclass
class Result:
    job:     Job
    passed:  bool
    elapsed: float          # seconds
    error:   str = ""       # non-empty when the subprocess itself failed


# ---------------------------------------------------------------------------
# Compile step
# ---------------------------------------------------------------------------
def compile_project(makefile_dir: Path) -> bool:
    """Run 'make compile' once before launching parallel runs."""
    print("▶  Compiling project (make compile) …")
    proc = subprocess.run(
        ["make", "compile"],
        cwd=makefile_dir,
        capture_output=False,   # let compile output flow to stdout
    )
    if proc.returncode != 0:
        print("✗  Compilation FAILED – aborting.", file=sys.stderr)
        return False
    print("✔  Compilation succeeded.\n")
    return True


# ---------------------------------------------------------------------------
# Single simulation run
# ---------------------------------------------------------------------------
def run_job(job: Job, makefile_dir: Path) -> Result:
    """
    Invoke 'make run TEST=<t> SEED=<s> WAVES=0' and decide pass/fail by
    scanning the log for Questa's standard PASS/FAIL markers.
    """
    cmd = [
        "make", "-s", "run",
        f"TEST={job.test}",
        f"SEED={job.seed}",
        "WAVES=0",
    ]

    t0 = time.monotonic()
    try:
        proc = subprocess.run(
            cmd,
            cwd=makefile_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        elapsed = time.monotonic() - t0
        log_text = proc.stdout or ""

        # Write log to disk
        job.log.parent.mkdir(parents=True, exist_ok=True)
        job.log.write_text(log_text)

        passed = _detect_pass(log_text, proc.returncode)
        return Result(job=job, passed=passed, elapsed=elapsed)

    except Exception as exc:
        elapsed = time.monotonic() - t0
        return Result(job=job, passed=False, elapsed=elapsed, error=str(exc))


def _detect_pass(log: str, returncode: int) -> bool:
    """
    Questa prints  '** Note: $finish ...'  on a clean exit and testbenches
    typically print a line containing PASS or FAIL.  We look for explicit
    FAIL/ERROR first, then look for PASS, then fall back to the exit code.
    """
    upper = log.upper()
    if "TEST FAILED" in upper or "** ERROR" in upper or "ASSERTION FAILED" in upper:
        return False
    if "TEST PASSED" in upper or "** PASS" in upper or "SIMULATION PASSED" in upper:
        return True
    # Fallback: trust the make exit code
    return returncode == 0


# ---------------------------------------------------------------------------
# Pretty summary
# ---------------------------------------------------------------------------
def print_summary(results: list[Result]) -> int:
    """Print a table and return the number of failures."""
    passed  = [r for r in results if r.passed]
    failed  = [r for r in results if not r.passed]
    total   = len(results)

    col_w = max(len(r.job.test) for r in results) + 2

    header = f"{'TEST':<{col_w}} {'SEED':>6}  {'STATUS':^8}  {'TIME':>8}  LOG"
    print("\n" + "=" * len(header))
    print(header)
    print("=" * len(header))

    for r in sorted(results, key=lambda x: (x.job.test, x.job.seed)):
        status = "PASS" if r.passed else "FAIL"
        mark   = "✔" if r.passed else "✗"
        note   = f"  ← {r.error}" if r.error else ""
        print(
            f"{mark} {r.job.test:<{col_w}} {r.job.seed:>6}  {status:^8}"
            f"  {r.elapsed:>6.1f}s  {r.job.log}{note}"
        )

    print("=" * len(header))
    print(f"  Total: {total}  |  Passed: {len(passed)}  |  Failed: {len(failed)}")
    print("=" * len(header) + "\n")

    if failed:
        print("Failed runs:")
        for r in failed:
            print(f"  • {r.job.test}  seed={r.job.seed}  →  {r.job.log}")
        print()

    return len(failed)


# ---------------------------------------------------------------------------
# CLI & main
# ---------------------------------------------------------------------------
def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Parallel SV regression runner")
    p.add_argument(
        "--seeds", nargs="+", type=int, default=DEFAULT_SEEDS,
        metavar="N",
        help=f"Seeds to use (default: {DEFAULT_SEEDS})",
    )
    p.add_argument(
        "--tests", nargs="+", default=ALL_TESTS,
        metavar="TEST",
        help="Test names to run (default: all regression tests)",
    )
    p.add_argument(
        "--workers", type=int, default=MAX_WORKERS,
        metavar="N",
        help=f"Max parallel jobs (default: {MAX_WORKERS})",
    )
    p.add_argument(
        "--compile", action="store_true",
        help="Run 'make compile' before launching jobs",
    )
    p.add_argument(
        "--makefile-dir", type=Path, default=Path("."),
        metavar="DIR",
        help="Directory containing the Makefile (default: current dir)",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()

    makefile_dir: Path = args.makefile_dir.resolve()
    BUILD_DIR.mkdir(parents=True, exist_ok=True)

    # Optional compile step
    if args.compile:
        if not compile_project(makefile_dir):
            return 1

    # Build job list: (test × seed)
    jobs = [Job(test=t, seed=s) for t in args.tests for s in args.seeds]
    total = len(jobs)
    workers = min(args.workers, total)

    print(
        f"▶  Launching {total} job(s)  "
        f"({len(args.tests)} test(s) × {len(args.seeds)} seed(s))  "
        f"with {workers} parallel worker(s)"
    )
    print(f"   Seeds  : {args.seeds}")
    print(f"   Tests  : {args.tests}")
    print(f"   Logs → : {BUILD_DIR}/\n")

    start = time.monotonic()
    results: list[Result] = []
    done = 0

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(run_job, job, makefile_dir): job for job in jobs}

        for future in as_completed(futures):
            result = future.result()
            done += 1
            status = "PASS" if result.passed else "FAIL"
            mark   = "✔" if result.passed else "✗"
            print(
                f"  [{done:>3}/{total}] {mark} {result.job.test}"
                f"  seed={result.job.seed}  ({result.elapsed:.1f}s)  [{status}]"
            )
            results.append(result)

    wall = time.monotonic() - start

    # ---------- timing summary ----------
    wall_h  = int(wall) // 3600
    wall_m  = (int(wall) % 3600) // 60
    wall_s  = wall % 60
    sim_total = sum(r.elapsed for r in results)   # sequential equivalent

    print(f"\n  ⏱  Started  : {datetime.fromtimestamp(start + time.time() - time.monotonic()).strftime('%H:%M:%S')}")
    print(f"  ⏱  Finished : {datetime.now().strftime('%H:%M:%S')}")
    if wall_h:
        print(f"  ⏱  Duration : {wall_h}h {wall_m}m {wall_s:.1f}s")
    elif wall_m:
        print(f"  ⏱  Duration : {wall_m}m {wall_s:.1f}s")
    else:
        print(f"  ⏱  Duration : {wall_s:.1f}s")
    print(f"  ⏱  Speedup  : {sim_total/wall:.1f}x  (would have taken {sim_total:.0f}s sequentially)")

    failures = print_summary(results)

    # ---------- coverage ----------
    print("\n▶  Merging coverage databases ...")
    ucdb_files = list(Path(".").glob("*.ucdb"))
    if not ucdb_files:
        print("  ⚠  No .ucdb files found - skipping coverage.", file=sys.stderr)
    else:
        merge = subprocess.run(
            ["vcover", "merge", "-out", "build/merged.ucdb"] + [str(f) for f in ucdb_files],
            capture_output=False,
        )
        if merge.returncode != 0:
            print("✗  Coverage merge failed.", file=sys.stderr)
        else:
            print("▶  Generating coverage report ...")
            with open("coverage_report.txt", "w") as rpt:
                cov = subprocess.run(
                    ["vcover", "report", "-details", "build/merged.ucdb"],
                    stdout=rpt,
                    stderr=subprocess.STDOUT,
                )
            if cov.returncode == 0:
                print("✔  Coverage report saved to: coverage_report.txt")
            else:
                print("✗  Coverage report generation failed.", file=sys.stderr)

    # Exit 0 if all passed, 1 otherwise (useful for CI)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
