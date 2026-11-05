from pathlib import Path
import shutil
import sys
from tempfile import TemporaryDirectory
import unittest

from check import run_check


class CheckRunnerTest(unittest.TestCase):
    def run_probe(self, source, timeout=5):
        return run_check([sys.executable, "-c", source], "PROBE_OK", timeout)

    def test_accepts_completed_check(self):
        self.assertEqual(self.run_probe("print('PROBE_OK: done')"), "PROBE_OK: done")

    def test_requires_completion_marker(self):
        with self.assertRaisesRegex(RuntimeError, "completion marker"):
            self.run_probe("print('started')")

    def test_rejects_script_errors_even_after_completion(self):
        with self.assertRaisesRegex(RuntimeError, "SCRIPT ERROR"):
            self.run_probe("print('SCRIPT ERROR: parse failed'); print('PROBE_OK')")

    def test_rejects_nonzero_exit_even_after_completion(self):
        with self.assertRaisesRegex(RuntimeError, "exit 2"):
            self.run_probe("print('PROBE_OK'); raise SystemExit(2)")

    def test_times_out(self):
        with self.assertRaisesRegex(RuntimeError, "timed out"):
            self.run_probe("import time; time.sleep(10)", timeout=0.1)

    def test_fresh_checkout_does_not_require_offline_intermediates(self):
        with TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "tools").mkdir()
            (root / "game/world").mkdir(parents=True)
            (root / "game/world/location_catalog.json").write_text("{}", encoding="utf-8")
            checker = root / "tools/check_structure.py"
            shutil.copyfile(Path(__file__).with_name(checker.name), checker)
            command = [sys.executable, str(checker)]
            self.assertIn("STRUCTURE_CHECK_OK", run_check(command, "STRUCTURE_CHECK_OK", 5))
            (root / "tools/generated").mkdir()
            with self.assertRaisesRegex(RuntimeError, "Offline intermediates"):
                run_check(command, "STRUCTURE_CHECK_OK", 5)


if __name__ == "__main__":
    unittest.main()
