import json, os, subprocess, sys, tempfile, unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "write_usage_cache.py"

def run(stdin_text, out_path):
    env = dict(os.environ, CLAUDE_USAGE_CACHE_PATH=str(out_path))
    return subprocess.run([sys.executable, str(SCRIPT)], input=stdin_text,
                          text=True, capture_output=True, env=env)

class WriteUsageCacheTest(unittest.TestCase):
    def test_writes_expected_shape(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "usage-cache.json"
            payload = json.dumps({"rate_limits": {
                "five_hour": {"used_percentage": 42.0, "resets_at": 1780041720},
                "seven_day": {"used_percentage": 18.0, "resets_at": 1780300800}}})
            r = run(payload, out)
            self.assertEqual(r.returncode, 0, r.stderr)
            data = json.loads(out.read_text())
            self.assertEqual(data["schema"], 1)
            self.assertIsInstance(data["captured_at"], int)
            self.assertEqual(data["five_hour"]["used_percentage"], 42.0)
            self.assertEqual(data["five_hour"]["resets_at"], 1780041720)
            self.assertEqual(data["seven_day"]["used_percentage"], 18.0)

    def test_no_tmp_residue(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "usage-cache.json"
            run(json.dumps({"rate_limits": {"five_hour": {"used_percentage": 1.0, "resets_at": 1}}}), out)
            leftovers = [p.name for p in Path(d).iterdir() if ".tmp" in p.name]
            self.assertEqual(leftovers, [])

    def test_missing_rate_limits_writes_nothing_and_exits_zero(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "usage-cache.json"
            r = run(json.dumps({"model": {"id": "x"}}), out)
            self.assertEqual(r.returncode, 0)
            self.assertFalse(out.exists())

    def test_invalid_json_exits_zero_no_file(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "usage-cache.json"
            r = run("not json", out)
            self.assertEqual(r.returncode, 0)
            self.assertFalse(out.exists())

if __name__ == "__main__":
    unittest.main()
