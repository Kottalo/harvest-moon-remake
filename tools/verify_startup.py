"""Launch the actual main scene repeatedly on an isolated Windows desktop."""
import argparse
import json
from pathlib import Path
from time import perf_counter
from run_render_check import run


def check(log_dir, runs):
    log_dir.mkdir(parents=True, exist_ok=True)
    results = []
    for index in range(runs):
        log = log_dir / f"startup-main-{index:02d}.txt"
        began = perf_counter()
        code = run(log, script=None, timeout=12,
                   extra_args=["--debug-collisions", "--quit-after", "30"])
        content = log.read_text(encoding="utf-8")
        assert code == 0 and "WORLD_READY:" in content and "BOOT_STAGE: player ready" in content, str(log)
        assert "SCRIPT ERROR" not in content and "ERROR:" not in content, str(log)
        results.append({"run": index, "elapsed_seconds": round(perf_counter()-began, 3)})
        print(f"MAIN_STARTUP_OK {index+1}/{runs}", flush=True)
    (log_dir / "startup-summary.json").write_text(json.dumps({"ok": True, "runs": results}, indent=2), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--log-dir", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=10)
    args = parser.parse_args()
    assert args.runs > 0
    check(args.log_dir.resolve(), args.runs)
