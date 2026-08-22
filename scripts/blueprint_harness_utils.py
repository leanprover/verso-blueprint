from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


@dataclass(frozen=True)
class StepFailure:
    step: str
    detail: str


def format_command(command: list[str]) -> str:
    return " ".join(command)


def run(command: list[str], *, cwd: Path) -> None:
    print(f"[blueprint-harness] $ {format_command(command)}")
    subprocess.run(command, cwd=cwd, check=True)


def format_elapsed(seconds: float) -> str:
    total_seconds = int(seconds)
    minutes, seconds = divmod(total_seconds, 60)
    if minutes:
        return f"{minutes}m{seconds:02d}s"
    return f"{seconds}s"


@contextmanager
def timed_step(label: str):
    start = time.monotonic()
    print(f"[blueprint-harness] starting {label}", flush=True)
    try:
        yield
    except BaseException:
        elapsed = format_elapsed(time.monotonic() - start)
        print(f"[blueprint-harness] failed {label} after {elapsed}", flush=True)
        raise
    else:
        elapsed = format_elapsed(time.monotonic() - start)
        print(f"[blueprint-harness] finished {label} in {elapsed}", flush=True)


def spawn_managed_process(command: list[str], *, cwd: Path) -> subprocess.Popen[bytes]:
    return subprocess.Popen(command, cwd=cwd, start_new_session=os.name == "posix")


def terminate_managed_process(proc: subprocess.Popen[bytes], *, timeout_seconds: int = 5) -> None:
    if proc.poll() is not None:
        return
    if os.name == "posix":
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            return
    else:
        proc.terminate()
    try:
        proc.wait(timeout=timeout_seconds)
        return
    except subprocess.TimeoutExpired:
        pass
    if os.name == "posix":
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            return
    else:
        proc.kill()
    proc.wait()


def run_with_heartbeat(
    command: list[str],
    *,
    cwd: Path,
    label: str,
    heartbeat_seconds: int = 60,
) -> None:
    print(f"[blueprint-harness] $ {format_command(command)}")
    with timed_step(label):
        start = time.monotonic()
        proc = spawn_managed_process(command, cwd=cwd)
        try:
            while True:
                try:
                    returncode = proc.wait(timeout=heartbeat_seconds)
                    break
                except subprocess.TimeoutExpired:
                    elapsed = format_elapsed(time.monotonic() - start)
                    print(
                        f"[blueprint-harness] still running {label} after {elapsed}: {format_command(command)}",
                        flush=True,
                    )
            if returncode != 0:
                raise subprocess.CalledProcessError(returncode, command)
        except BaseException:
            terminate_managed_process(proc)
            raise


def run_capturing_failure(step: str, command: list[str], *, cwd: Path) -> StepFailure | None:
    try:
        run(command, cwd=cwd)
        return None
    except subprocess.CalledProcessError as err:
        return StepFailure(step=step, detail=f"exit code {err.returncode}: {format_command(command)}")


def print_failure_summary(failures: list[StepFailure], *, prefix: str) -> int:
    if not failures:
        print(f"{prefix} validation summary: all requested steps passed")
        return 0

    print(f"{prefix} validation summary: failures detected", file=sys.stderr)
    for failure in failures:
        print(f"{prefix}   {failure.step}: {failure.detail}", file=sys.stderr)
    return 1


def lean_low_priority_command(package_root: Path, *args: str) -> list[str]:
    return [str(package_root / "scripts" / "lean-low-priority"), *args]
