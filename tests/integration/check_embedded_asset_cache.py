from __future__ import annotations

import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile


PACKAGE_ROOT = Path(__file__).resolve().parents[2]
LEAN_TOOLCHAIN = (PACKAGE_ROOT / "lean-toolchain").read_text(encoding="utf-8")
LEAN_LOW_PRIORITY = PACKAGE_ROOT / "scripts" / "lean-low-priority"

BASELINE_ASSET = "embedded-asset-cache-baseline"
CHANGED_ASSET = "embedded-asset-cache-changed"

LAKEFILE = """import Lake
open Lake DSL

package AssetCacheRegression where
  precompileModules := false
  leanOptions := #[⟨`experimental.module, true⟩]

input_dir embeddedAssets where
  path := "assets"
  text := true
  filter := .extension <| .mem #["css"]

lean_lib AssetCacheRegression where
  roots := #[`AssetValue]
  needs := #[embeddedAssets]

@[default_target]
lean_exe assetCacheRegression where
  root := `Main
"""

ASSET_VALUE = """def embeddedAsset : String :=
  include_str "assets/asset.css"
"""

MAIN = """import AssetValue

def main : IO Unit :=
  IO.println embeddedAsset
"""


def run(
    command: list[str],
    *,
    cwd: Path,
    env: dict[str, str],
) -> subprocess.CompletedProcess[str]:
    print(f"[embedded-asset-cache] $ {shlex.join(command)}", flush=True)
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        raise SystemExit(
            f"[embedded-asset-cache] command failed with exit code {result.returncode}\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )
    return result


def cache_environment(cache_dir: Path) -> dict[str, str]:
    env = {
        key: value
        for key, value in os.environ.items()
        if key
        not in {
            "LAKE_ARTIFACT_CACHE",
            "LAKE_CACHE_DIR",
            "LAKE_NO_CACHE",
            "LAKE_RESTORE_ARTIFACTS",
        }
    }
    env.update(
        {
            "LAKE_ARTIFACT_CACHE": "true",
            "LAKE_CACHE_DIR": str(cache_dir),
            "LAKE_RESTORE_ARTIFACTS": "false",
        }
    )
    return env


def write_asset(project_dir: Path, value: str) -> None:
    (project_dir / "assets" / "asset.css").write_text(f"{value}\n", encoding="utf-8")


def remove_build_tree(project_dir: Path) -> None:
    build_dir = project_dir / ".lake" / "build"
    if build_dir.exists():
        shutil.rmtree(build_dir)


def build(project_dir: Path, env: dict[str, str], *, no_build: bool = False) -> None:
    command = [str(LEAN_LOW_PRIORITY), "lake", "build", "assetCacheRegression"]
    if no_build:
        command.extend(["--no-build", "--wfail"])
    run(command, cwd=project_dir, env=env)


def assert_embedded_output(project_dir: Path, env: dict[str, str], expected: str) -> None:
    result = run(
        [str(LEAN_LOW_PRIORITY), "lake", "exe", "assetCacheRegression"],
        cwd=project_dir,
        env=env,
    )
    if result.stdout.strip() != expected:
        raise SystemExit(
            f"[embedded-asset-cache] expected generated output {expected!r}, "
            f"got {result.stdout.strip()!r}\n"
            f"stderr:\n{result.stderr}"
        )


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="verso-blueprint-embedded-asset-cache-") as tmp:
        workspace = Path(tmp)
        project_dir = workspace / "project"
        cache_dir = workspace / "cache"
        project_dir.mkdir()
        (project_dir / "assets").mkdir()

        (project_dir / "lean-toolchain").write_text(LEAN_TOOLCHAIN, encoding="utf-8")
        (project_dir / "lakefile.lean").write_text(LAKEFILE, encoding="utf-8")
        (project_dir / "AssetValue.lean").write_text(ASSET_VALUE, encoding="utf-8")
        (project_dir / "Main.lean").write_text(MAIN, encoding="utf-8")

        env = cache_environment(cache_dir)

        # The changed asset must not reuse stale baseline output. Returning to
        # the baseline under --no-build then proves its exact artifact survived.
        write_asset(project_dir, BASELINE_ASSET)
        build(project_dir, env)
        assert_embedded_output(project_dir, env, BASELINE_ASSET)

        remove_build_tree(project_dir)
        write_asset(project_dir, CHANGED_ASSET)
        build(project_dir, env)
        assert_embedded_output(project_dir, env, CHANGED_ASSET)

        remove_build_tree(project_dir)
        write_asset(project_dir, BASELINE_ASSET)
        build(project_dir, env, no_build=True)
        assert_embedded_output(project_dir, env, BASELINE_ASSET)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
