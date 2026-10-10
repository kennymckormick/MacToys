import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from portman import client
from portman.common import PortmanError, user_context_command


class SessionRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="portman-recovery-test-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.runtime = {"pid": 12345, "port": 45678, "token": "test-only"}
        (self.home / "runtime.json").write_text(json.dumps(self.runtime))
        self.saved = b'{"version":1,"mappings":[{"name":"preserve me"}]}\n'
        (self.home / "mappings.json").write_bytes(self.saved)
        self.mappings = [{"enabled": True, "mode": "ssh-local", "status": "retrying",
                          "error": "No user exists for uid {}".format(os.getuid())}]
        self.calls = []
        self.platform = patch.object(client.sys, "platform", "darwin")
        self.platform.start()
        self.addCleanup(self.platform.stop)

    def request(self, runtime, path, data=None, **kwargs):
        self.assertEqual(runtime, self.runtime)
        self.calls.append(path)
        if path == "/api/mappings":
            return {"mappings": copy.deepcopy(self.mappings)}
        if path == "/api/shutdown":
            (self.home / "runtime.json").unlink()
            return {"stopping": True}
        self.fail("Unexpected API request: " + path)

    def repair(self, probe_code=0):
        with patch.object(client, "request", side_effect=self.request), \
             patch.object(client, "running", return_value=self.runtime), \
             patch.object(client.subprocess, "run", return_value=subprocess.CompletedProcess([], probe_code)) as probe:
            result = client.recover_session(self.home, self.runtime)
        self.assertEqual((self.home / "mappings.json").read_bytes(), self.saved)
        return result, probe

    def test_recovers_legacy_daemon_without_changing_saved_rules(self):
        result, probe = self.repair()
        self.assertIsNone(result)
        self.assertEqual(self.calls.count("/api/shutdown"), 1)
        self.assertIn("attempted_at", json.loads((self.home / "recovery.json").read_text()))
        self.assertEqual((self.home / "recovery.lock").stat().st_mode & 0o777, 0o600)
        self.assertEqual(probe.call_args.args[0][-5:], ["/usr/bin/ssh", "-G", "-F", os.devnull, "localhost"])

    def test_preserves_running_and_starting_forwards(self):
        for state in ("running", "starting", "unknown"):
            with self.subTest(state=state):
                self.mappings.append({"enabled": True, "mode": "tcp", "status": state})
                result, probe = self.repair()
                self.assertEqual(result, self.runtime)
                self.assertNotIn("/api/shutdown", self.calls)
                probe.assert_not_called()
                self.mappings.pop()

    def test_does_not_restart_for_remote_auth_network_or_other_uid_errors(self):
        for error in ("Permission denied (publickey).", "Connection timed out",
                      "No user exists for uid {}".format(os.getuid() + 1),
                      "remote: No user exists for uid {}".format(os.getuid())):
            with self.subTest(error=error):
                self.mappings[0]["error"] = error
                result, probe = self.repair()
                self.assertEqual(result, self.runtime)
                self.assertNotIn("/api/shutdown", self.calls)
                probe.assert_not_called()

    def test_stopped_or_non_ssh_mapping_does_not_trigger_recovery(self):
        for changes in ({"enabled": False}, {"status": "stopped"}, {"mode": "tcp"}):
            original = self.mappings[0].copy()
            self.mappings[0].update(changes)
            result, probe = self.repair()
            self.assertEqual(result, self.runtime)
            self.assertNotIn("/api/shutdown", self.calls)
            probe.assert_not_called()
            self.mappings[0] = original

    def test_unhealthy_client_cannot_shut_down_daemon(self):
        result, _ = self.repair(probe_code=255)
        self.assertEqual(result, self.runtime)
        self.assertNotIn("/api/shutdown", self.calls)
        self.assertFalse((self.home / "recovery.json").exists())

    def test_probe_timeout_leaves_daemon_running(self):
        with patch.object(client, "request", side_effect=self.request), \
             patch.object(client, "running", return_value=self.runtime), \
             patch.object(client.subprocess, "run", side_effect=subprocess.TimeoutExpired("ssh", 5)):
            self.assertEqual(client.recover_session(self.home, self.runtime), self.runtime)
        self.assertNotIn("/api/shutdown", self.calls)

    def test_cooldown_prevents_restart_loop_across_clients(self):
        (self.home / "recovery.json").write_text(json.dumps({"attempted_at": client.time.time()}))
        result, probe = self.repair()
        self.assertEqual(result, self.runtime)
        self.assertNotIn("/api/shutdown", self.calls)
        probe.assert_not_called()

    def test_concurrent_replacement_is_reused(self):
        replacement = dict(self.runtime, pid=67890, token="another-test-only-token")
        with patch.object(client, "request", side_effect=self.request), \
             patch.object(client, "running", return_value=replacement):
            self.assertEqual(client.recover_session(self.home, self.runtime), replacement)
        self.assertNotIn("/api/shutdown", self.calls)

    def test_unresponsive_api_is_not_treated_as_user_lookup_failure(self):
        with patch.object(client, "request", side_effect=PortmanError("API unavailable")):
            self.assertEqual(client.recover_session(self.home, self.runtime), self.runtime)

    def test_slow_shutdown_is_not_force_killed(self):
        def request(runtime, path, data=None, **kwargs):
            if path == "/api/shutdown":
                return {"stopping": True}
            return self.request(runtime, path, data, **kwargs)
        with patch.object(client, "request", side_effect=request), \
             patch.object(client, "running", return_value=self.runtime), \
             patch.object(client.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)), \
             patch.object(client.time, "monotonic", side_effect=[0, 11]):
            with self.assertRaisesRegex(PortmanError, "waiting for the old background service"):
                client.recover_session(self.home, self.runtime)

    def test_other_platforms_keep_existing_behavior(self):
        with patch.object(client.sys, "platform", "linux"), \
             patch.object(client, "request") as request:
            self.assertEqual(client.recover_session(self.home, self.runtime), self.runtime)
            self.assertEqual(user_context_command(["python", "-m", "portman"]), ["python", "-m", "portman"])
            request.assert_not_called()

    def test_macos_launch_keeps_same_user_and_arguments(self):
        self.assertEqual(user_context_command(["/path with spaces/python", "--home", "a b"]),
                         ["/bin/launchctl", "asuser", str(os.getuid()), "/path with spaces/python", "--home", "a b"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
