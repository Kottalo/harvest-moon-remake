"""Run the existing Godot behavior checks without opening the editor."""
import argparse
from pathlib import Path
import subprocess
import sys
from time import perf_counter


ROOT = Path(__file__).resolve().parents[1]
GODOT = ROOT.parent / "Tools/Godot/Godot_v4.7.2-stable_win64.exe"
GROUPS = {
    "smoke": {"runtime": "NATIVE_CHECK_OK"},
    "camera": {"camera_limits": "CAMERA_LIMITS_OK", "blocked_camera": "BLOCKED_CAMERA_OK"},
    "player": {"collision": "COLLISION_CHECK_OK", "hop_ground": "HOP_GROUND_OK",
               "tool_switch": "TOOL_SWITCH_OK", "actions": "ACTIONS_CHECK_OK", "rucksack": "RUCKSACK_OK"},
    "field": {"crops": "CROPS_OK", "item_collision": "ITEM_COLLISION_CHECK_OK",
              "mine_dig": "MINE_DIG_OK"},
    "world": {"door_access": "DOOR_ACCESS_OK", "door_entry": "DOOR_ENTRY_CHECK_OK",
              "door_exit": "DOOR_EXIT_CHECK_OK", "stair_transitions": "STAIR_TRANSITIONS_OK",
              "coast": "COAST_CHECK_OK"},
    "debug": {"debug_scenes": "DEBUG_SCENES_OK"},
    "npc": {"npc_navigation": "NPC_NAVIGATION_OK", "npc_roster": "NPC_ROSTER_OK"},
    "economy": {"economy": "ECONOMY_OK"},
    "time": {"day_cycle": "DAY_CYCLE_CHECK_OK", "day_debug": "DAY_DEBUG_CHECK_OK"},
}
DUAL_RATE = {"blocked_camera", "collision", "hop_ground", "coast", "npc_navigation"}


def run_check(command, marker, timeout):
    try:
        result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                encoding="utf-8", errors="replace", timeout=timeout)
    except subprocess.TimeoutExpired as error:
        tail = (error.output or b"").decode("utf-8", errors="replace")
        raise RuntimeError(f"timed out after {timeout}s\n{tail[-6000:]}") from error
    output = result.stdout
    if result.returncode != 0 or "SCRIPT ERROR:" in output:
        raise RuntimeError(f"exit {result.returncode}\n{output[-6000:]}")
    for line in output.splitlines():
        if line == marker or line.startswith(marker + ":"):
            return line
    raise RuntimeError(f"missing completion marker {marker}\n{output[-6000:]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("groups", nargs="*", metavar="GROUP", help="named check groups, default smoke")
    parser.add_argument("--list", action="store_true", help="show groups and scripts")
    parser.add_argument("--godot", type=Path, default=GODOT, help="path to the Godot engine executable")
    parser.add_argument("--timeout", type=int, default=60, help="maximum seconds per check")
    args = parser.parse_args()
    if args.list:
        for name, checks in GROUPS.items():
            print(f"{name}: " + ", ".join(f"verify_{check}.gd" for check in checks))
        return 0
    groups = args.groups or ["smoke"]
    if unknown := sorted(set(groups) - GROUPS.keys()):
        parser.error(f"unknown group {', '.join(unknown)}; use --list")
    godot = args.godot.resolve()
    if not godot.is_file():
        parser.error(f"Godot executable missing: {godot}; pass --godot")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")

    label = "structure"
    began = perf_counter()
    checks = {check: marker for group in groups for check, marker in GROUPS[group].items()}
    try:
        print(run_check([sys.executable, "tools/check_structure.py"], "STRUCTURE_CHECK_OK", args.timeout), flush=True)
        for check, marker in checks.items():
            for rate in (60, 120) if check in DUAL_RATE else (60,):
                label = f"{check} ({rate} Hz)"
                start = perf_counter()
                command = [str(godot), "--headless", "--path", str(ROOT)]
                if check != "runtime":
                    command += ["--fixed-fps", str(rate)]
                command += ["--script", f"tools/verify_{check}.gd"]
                if rate == 120:
                    command += ["--", "--120hz"]
                result = run_check(command, marker, args.timeout)
                print(f"{label} [{perf_counter() - start:.1f}s] {result}", flush=True)
    except (OSError, RuntimeError) as error:
        print(f"CHECK FAILED: {label}\n{error}", file=sys.stderr)
        return 1
    print(f"CHECKS_OK: {', '.join(groups)} [{perf_counter() - began:.1f}s]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
