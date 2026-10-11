import asyncio
import copy
import fcntl
from http.client import RemoteDisconnected
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import call, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from portman import client
from portman import cli
from portman.common import PortmanError, user_context_command, session_recovery_needed
from portman.manager import Manager


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
        if path == "/api/recover-session":
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

    def test_recovers_daemon_without_changing_saved_rules(self):
        result, probe = self.repair()
        self.assertIsNone(result)
        self.assertEqual(self.calls.count("/api/recover-session"), 1)
        self.assertNotIn("/api/shutdown", self.calls)
        self.assertIn("attempted_at", json.loads((self.home / "recovery.json").read_text()))
        self.assertEqual((self.home / "recovery.lock").stat().st_mode & 0o777, 0o600)
        self.assertEqual(probe.call_args.args[0][-5:], ["/usr/bin/ssh", "-G", "-F", os.devnull, "localhost"])

    def test_preserves_running_and_starting_forwards(self):
        for state in ("running", "starting", "unknown"):
            with self.subTest(state=state):
                self.mappings.append({"enabled": True, "mode": "tcp", "status": state})
                result, probe = self.repair()
                self.assertEqual(result, self.runtime)
                self.assertNotIn("/api/recover-session", self.calls)
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
                self.assertNotIn("/api/recover-session", self.calls)
                probe.assert_not_called()

    def test_stopped_or_non_ssh_mapping_does_not_trigger_recovery(self):
        for changes in ({"enabled": False}, {"status": "stopped"}, {"mode": "tcp"}):
            original = self.mappings[0].copy()
            self.mappings[0].update(changes)
            result, probe = self.repair()
            self.assertEqual(result, self.runtime)
            self.assertNotIn("/api/recover-session", self.calls)
            probe.assert_not_called()
            self.mappings[0] = original

    def test_unhealthy_client_cannot_shut_down_daemon(self):
        result, _ = self.repair(probe_code=255)
        self.assertEqual(result, self.runtime)
        self.assertNotIn("/api/recover-session", self.calls)
        self.assertFalse((self.home / "recovery.json").exists())

    def test_probe_timeout_leaves_daemon_running(self):
        with patch.object(client, "request", side_effect=self.request), \
             patch.object(client, "running", return_value=self.runtime), \
             patch.object(client.subprocess, "run", side_effect=subprocess.TimeoutExpired("ssh", 5)):
            self.assertEqual(client.recover_session(self.home, self.runtime), self.runtime)
        self.assertNotIn("/api/recover-session", self.calls)

    def test_cooldown_prevents_restart_loop_across_clients(self):
        (self.home / "recovery.json").write_text(json.dumps({"attempted_at": client.time.time()}))
        result, probe = self.repair()
        self.assertEqual(result, self.runtime)
        self.assertNotIn("/api/recover-session", self.calls)
        probe.assert_not_called()

    def test_concurrent_replacement_is_reused(self):
        replacement = dict(self.runtime, pid=67890, token="another-test-only-token")
        with patch.object(client, "request", side_effect=self.request), \
             patch.object(client, "running", return_value=replacement):
            self.assertEqual(client.recover_session(self.home, self.runtime), replacement)
        self.assertNotIn("/api/recover-session", self.calls)

    def test_unresponsive_api_is_not_treated_as_user_lookup_failure(self):
        with patch.object(client, "request", side_effect=PortmanError("API unavailable")):
            self.assertEqual(client.recover_session(self.home, self.runtime), self.runtime)

    def test_slow_shutdown_is_not_force_killed(self):
        def request(runtime, path, data=None, **kwargs):
            if path == "/api/recover-session":
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

    def test_corrupt_or_future_cooldown_does_not_disable_recovery(self):
        for value in ("{broken", "[]", "null", '{"attempted_at":"invalid"}',
                      '{"attempted_at":true}', '{"attempted_at":NaN}',
                      '{"attempted_at":Infinity}', json.dumps({"attempted_at": 10**400}),
                      json.dumps({"attempted_at": client.time.time() + 86400})):
            with self.subTest(value=value[:80]):
                (self.home / "runtime.json").write_text(json.dumps(self.runtime))
                (self.home / "recovery.json").write_text(value)
                self.calls.clear()
                result, _ = self.repair()
                self.assertIsNone(result)
                self.assertEqual(self.calls.count("/api/recover-session"), 1)

    def test_concurrent_recovery_lock_never_blocks_client(self):
        with (self.home / "recovery.lock").open("a+") as other:
            fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)
            started = client.time.monotonic()
            result, probe = self.repair()
        self.assertLess(client.time.monotonic() - started, 1)
        self.assertEqual(result, self.runtime)
        probe.assert_not_called()
        self.assertNotIn("/api/recover-session", self.calls)

    def test_api_disappearing_during_recheck_does_not_shutdown(self):
        with patch.object(client, "needs_session_recovery", side_effect=[True, PortmanError("API unavailable")]), \
             patch.object(client, "running", return_value=self.runtime), \
             patch.object(client, "request") as request:
            self.assertEqual(client.recover_session(self.home, self.runtime), self.runtime)
        request.assert_not_called()

    def test_server_veto_or_legacy_api_never_falls_back_to_shutdown(self):
        for response in ({"stopping": False}, PortmanError("Unknown action"), PortmanError("Timed out")):
            with self.subTest(response=response):
                (self.home / "recovery.json").unlink(missing_ok=True)
                self.calls.clear()
                def request(runtime, path, data=None, **kwargs):
                    if path == "/api/recover-session":
                        self.calls.append(path)
                        self.assertEqual(kwargs["timeout"], 2)
                        if isinstance(response, Exception):
                            raise response
                        return response
                    return self.request(runtime, path, data, **kwargs)
                with patch.object(client, "request", side_effect=request), \
                     patch.object(client, "running", return_value=self.runtime), \
                     patch.object(client.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)):
                    self.assertEqual(client.recover_session(self.home, self.runtime), self.runtime)
                self.assertNotIn("/api/shutdown", self.calls)
                self.assertTrue((self.home / "runtime.json").exists())

    def test_malformed_mapping_data_cannot_authorize_shutdown(self):
        for mappings in (None, {}, [], [None], [dict(self.mappings[0], error=None)],
                         [dict(self.mappings[0], enabled="true")]):
            with self.subTest(mappings=mappings):
                self.assertFalse(session_recovery_needed(mappings))

    def test_macos_launch_keeps_same_user_and_arguments(self):
        self.assertEqual(user_context_command(["/path with spaces/python", "--home", "a b"]),
                         ["/bin/launchctl", "asuser", str(os.getuid()), "/path with spaces/python", "--home", "a b"])


class ConcurrentReadTests(unittest.TestCase):
    def setUp(self):
        self.home = Path("/unused-test-state")
        self.old = {"pid": 12345, "port": 45678, "token": "old-test-token"}
        self.new = {"pid": 12346, "port": 45679, "token": "new-test-token"}

    def test_read_follows_replacement_after_connection_reset(self):
        result = {"ok": True, "pid": self.new["pid"]}
        with patch.object(client, "request", side_effect=[client.DaemonUnavailable("reset"), result]) as request, \
             patch.object(client, "running", side_effect=[self.old, None, self.new]), \
             patch.object(client.time, "sleep"):
            self.assertEqual(client.read_current(self.home, self.old, "/api/health"), (self.new, result))
        self.assertEqual(request.call_args_list, [call(self.old, "/api/health"), call(self.new, "/api/health")])

    def test_disconnected_http_response_is_retryable(self):
        for error in (ConnectionResetError("reset"), RemoteDisconnected("daemon exited")):
            with self.subTest(error=error), patch.object(client, "build_opener") as opener:
                opener.return_value.open.side_effect = error
                with self.assertRaises(client.DaemonUnavailable):
                    client.request(self.old, "/api/health")

    def test_application_error_is_not_retried(self):
        with patch.object(client, "request", side_effect=PortmanError("Unknown mapping")) as request, \
             patch.object(client, "running") as running:
            with self.assertRaisesRegex(PortmanError, "Unknown mapping"):
                client.read_current(self.home, self.old, "/api/logs?name=missing")
        request.assert_called_once()
        running.assert_not_called()

    def test_missing_replacement_has_a_bounded_wait_and_preserves_error(self):
        error = client.DaemonUnavailable("original connection reset")
        with patch.object(client, "request", side_effect=error) as request, \
             patch.object(client, "running", return_value=self.old), \
             patch.object(client.time, "monotonic", side_effect=[0, 0, 9]), \
             patch.object(client.time, "sleep"):
            with self.assertRaises(client.DaemonUnavailable) as raised:
                client.read_current(self.home, self.old, "/api/health")
        self.assertIs(raised.exception, error)
        request.assert_called_once()

    def test_mutation_is_never_replayed_after_connection_reset(self):
        with patch.object(cli, "ensure", return_value=self.old), \
             patch.object(cli, "request", side_effect=client.DaemonUnavailable("reset")) as request, \
             patch.object(cli, "read_current") as read, redirect_stdout(io.StringIO()):
            self.assertEqual(cli.main(["--home", str(self.home), "--json", "restart", "test-only"]), 1)
        request.assert_called_once_with(self.old, "/api/restart", {"name": "test-only"})
        read.assert_not_called()


class RecoveryAdmissionTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="portman-admission-test-")
        self.addCleanup(self.temp.cleanup)
        self.manager = Manager(Path(self.temp.name))
        self.addAsyncCleanup(self.manager.close)
        self.platform = patch.object(client.sys, "platform", "darwin")
        self.platform.start()
        self.addCleanup(self.platform.stop)
        await self.manager.dispatch("add", {"start": False, "spec": {
            "name": "test-only", "mode": "ssh-local", "listen": "127.0.0.1:18003",
            "target": "127.0.0.1:18000", "via": "test-only.invalid"}})
        self.mapping = self.manager.get("test-only")
        self.mapping.record["enabled"] = True
        self.mapping.state = "retrying"
        self.mapping.error = "No user exists for uid {}".format(os.getuid())
        self.manager.save()

    async def test_recovery_checks_current_state_not_client_snapshot(self):
        self.assertTrue(session_recovery_needed([self.mapping.snapshot()]))
        for state in ("running", "starting"):
            self.mapping.state = state
            self.assertEqual(await self.manager.dispatch("recover-session", {}), {"stopping": False})
            self.assertFalse(self.manager.stopping)

    async def test_recovery_never_queues_behind_inflight_mutation(self):
        async with self.manager.lock:
            result = await asyncio.wait_for(self.manager.dispatch("recover-session", {}), timeout=0.5)
        self.assertEqual(result, {"stopping": False})
        self.assertFalse(self.manager.stopping)

    async def test_accepted_recovery_blocks_new_mutations_and_keeps_rules(self):
        path = self.manager.home / "mappings.json"
        saved = path.read_bytes()
        self.assertEqual(await self.manager.dispatch("recover-session", {}), {"stopping": True})
        for action in ("start", "restart", "stop", "remove", "edit", "add"):
            with self.assertRaisesRegex(PortmanError, "stopping"):
                await self.manager.dispatch(action, {"name": "test-only"})
        self.assertEqual(path.read_bytes(), saved)

    async def test_retry_task_cannot_start_after_recovery_is_accepted(self):
        await self.manager.dispatch("recover-session", {})
        with patch.object(self.mapping, "start_ssh", side_effect=AssertionError("Must not launch another SSH")) as launch:
            await asyncio.wait_for(self.mapping.run(), timeout=0.5)
        launch.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
