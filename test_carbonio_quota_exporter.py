import contextlib
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import carbonio_quota_exporter as exporter


class QuotaExporterTests(unittest.TestCase):
    def test_sizes_and_quota(self):
        for value, expected in (
            ("1.5 MB", 1572864),
            ("2", 2097152),
            ("512 B", 512),
            ("1 GB", 1073741824),
        ):
            with self.subTest(value=value):
                self.assertEqual(exporter.mailbox_used_bytes(value), expected)
        self.assertEqual(exporter.mailbox_quota_bytes("# name user\nzimbraMailQuota: 0\n"), 0)
        with self.assertRaises(ValueError):
            exporter.mailbox_used_bytes("unknown")
        with self.assertRaises(ValueError):
            exporter.mailbox_quota_bytes("# no quota\n")

    @patch("carbonio_quota_exporter.subprocess.run")
    def test_collects_and_quotes_accounts(self, run):
        run.side_effect = [
            subprocess.CompletedProcess([], 0, "alice@example.test\nodd'\"@example.test\n", ""),
            subprocess.CompletedProcess([], 0, "1.5 MB\n", ""),
            subprocess.CompletedProcess([], 0, "zimbraMailQuota: 10485760\n", ""),
            subprocess.CompletedProcess([], 0, "512 B\n", ""),
            subprocess.CompletedProcess([], 0, "zimbraMailQuota: 0\n", ""),
        ]
        result = exporter.collect_metrics()
        self.assertIn('carbonio_mailbox_quota_bytes{account="alice@example.test"} 10485760\n', result)
        self.assertIn('carbonio_mailbox_used_bytes{account="alice@example.test"} 1572864\n', result)
        self.assertIn('carbonio_mailbox_used_bytes{account="odd\'\\"@example.test"} 512\n', result)
        self.assertEqual(
            run.call_args_list[3].args[0],
            ["su", "-", "zextras", "-c", """zmmailbox -z -m 'odd'"'"'"@example.test' gms"""],
        )

    @patch("carbonio_quota_exporter.run_as_zextras")
    def test_failed_collection_preserves_existing_file(self, run):
        run.side_effect = ["alice@example.test\n", "invalid"]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "quotas.prom"
            path.write_text("previous metrics\n", encoding="utf-8")
            with patch.object(sys, "argv", ["exporter", "--output", str(path)]):
                with contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(exporter.main(), 1)
            self.assertEqual(path.read_text(encoding="utf-8"), "previous metrics\n")
            self.assertEqual(list(Path(directory).iterdir()), [path])

    @patch("carbonio_quota_exporter.run_as_zextras")
    def test_successful_export_and_empty_accounts(self, run):
        run.return_value = ""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "quotas.prom"
            with patch.object(sys, "argv", ["exporter", "--output", str(path)]):
                self.assertEqual(exporter.main(), 0)
            self.assertIn("# TYPE carbonio_mailbox_used_bytes gauge\n", path.read_text(encoding="utf-8"))
            self.assertEqual(path.stat().st_mode & 0o777, 0o644)


if __name__ == "__main__":
    unittest.main()
