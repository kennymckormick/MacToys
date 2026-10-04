import concurrent.futures
import contextlib
import getpass
import http.client
import http.server
import json
import os
import signal
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from portman.common import PortmanError, endpoint, validate_spec, python_command


def free_port(ip="127.0.0.1"):
    with socket.socket(socket.AF_INET6 if ":" in ip else socket.AF_INET) as s:
        s.bind((ip, 0))
        return s.getsockname()[1]


def reachable(port):
    try:
        with socket.create_connection(("127.0.0.1", port), 0.2):
            return True
    except OSError:
        return False


def wait_for(fn, timeout=10):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        value = fn()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError("Condition did not become true in {} seconds".format(timeout))


class Echo(socketserver.BaseRequestHandler):
    def handle(self):
        # Reply only after client half-closes: tests correct TCP EOF propagation.
        data = bytearray()
        while True:
            chunk = self.request.recv(65536)
            if not chunk:
                break
            data.extend(chunk)
        with contextlib.suppress(OSError):
            self.request.sendall(data)


class TCPServer(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True


class HTTP(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"portman-through-the-forward"
        self.send_response(401)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


class SpecTests(unittest.TestCase):
    def test_worker_exits_cleanly_while_parent_pipe_is_open(self):
        with subprocess.Popen(python_command("portman.ssh_worker", "/usr/bin/true"),
                              stdin=subprocess.PIPE, stderr=subprocess.PIPE) as worker:
            self.assertEqual(worker.wait(timeout=5), 0, worker.stderr.read().decode())
            self.assertNotIn(b"Fatal Python error", worker.stderr.read())

    def test_worker_stops_child_when_parent_pipe_closes(self):
        worker = subprocess.Popen(python_command("portman.ssh_worker", "/bin/sleep", "30"),
                                  stdin=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            _, error = worker.communicate(timeout=5)
            self.assertEqual(worker.returncode, 1, error.decode())
        finally:
            if worker.poll() is None:
                worker.terminate()
                worker.wait(timeout=5)

    def test_control_server_starts_without_dns(self):
        from unittest.mock import patch
        from portman.service import Server, Handler
        with patch("socket.getfqdn", side_effect=AssertionError("Local API must not resolve DNS")):
            server = Server(("127.0.0.1", 0), Handler)
            try:
                self.assertEqual(server.server_name, "127.0.0.1")
                self.assertGreater(server.server_port, 0)
            finally:
                server.server_close()

    def test_ipv6_hostname_and_invalid_input(self):
        self.assertEqual(endpoint("[::1]:8000"), ("::1", 8000))
        self.assertEqual(endpoint("localhost:8000"), ("localhost", 8000))
        for value in ("::1:8000", "host:0", "host:65536", "-oops:80", "example.com;whoami:80", "x:NaN"):
            with self.subTest(value=value), self.assertRaises(PortmanError):
                endpoint(value)
        for via in ("-oProxyCommand=whoami", "user@host;echo", "bad user@host"):
            with self.subTest(via=via), self.assertRaises(PortmanError):
                validate_spec(dict(name="x", listen="18000", target="localhost:8000", via=via))


class LiveTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="portman-test-")
        self.home = Path(self.tmp.name) / "state"
        self.env = dict(os.environ, PORTMAN_HOME=str(self.home))
        self.echo = TCPServer(("127.0.0.1", 0), Echo)
        self.target = self.echo.server_address[1]
        threading.Thread(target=self.echo.serve_forever, daemon=True).start()
        self.addCleanup(self.cleanup)

    def cleanup(self):
        self.cli("daemon", "stop", check=False)
        self.echo.shutdown()
        self.echo.server_close()
        self.tmp.cleanup()

    def cli(self, *args, check=True):
        p = subprocess.run([sys.executable, "-m", "portman", *args, "--json"], cwd=str(ROOT), env=self.env,
                           capture_output=True, text=True, timeout=40)
        if check and p.returncode != 0:
            self.fail("CLI {} failed ({}): {} {}".format(args, p.returncode, p.stdout, p.stderr))
        try:
            result = json.loads(p.stdout)
        except ValueError:
            self.fail("CLI did not return JSON: " + p.stdout + p.stderr)
        return result if check else (p.returncode, result)

    def add(self, name="echo", **kwargs):
        port = free_port()
        args = ["add", name, "--listen", str(port), "--target", "localhost:" + str(self.target)]
        for key, value in kwargs.items():
            args += ["--" + key.replace("_", "-"), str(value)]
        return port, self.cli(*args)

    def transfer(self, port, data=b"hello", ip="127.0.0.1"):
        with socket.create_connection((ip, port), 8) as s:
            s.settimeout(8)
            s.sendall(data)
            s.shutdown(socket.SHUT_WR)
            chunks = []
            while True:
                b = s.recv(65536)
                if not b:
                    break
                chunks.append(b)
        self.assertEqual(b"".join(chunks), data)

    def runtime(self):
        return json.loads((self.home / "runtime.json").read_text())

    def test_tcp_data_concurrency_half_close_and_lifecycle(self):
        port, m = self.add()
        self.assertEqual(m["status"], "running")
        data = os.urandom(1024 * 1024 + 31)
        self.transfer(port, data)
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(lambda _: self.transfer(port, data[:65537]), range(12)))
        saved = self.cli("list")["mappings"][0]
        self.assertGreaterEqual(saved["bytes_up"], len(data))
        self.cli("stop", "echo")
        self.assertFalse(reachable(port))
        self.cli("start", "echo")
        self.transfer(port)
        self.cli("restart", "echo")
        self.transfer(port)
        self.cli("remove", "echo")
        self.assertFalse(reachable(port))
        self.assertEqual(self.cli("list")["mappings"], [])

    def test_edits_idempotency_and_invalid_update_preserves_live_forward(self):
        port, m = self.add()
        again = self.cli("add", "echo", "--listen", str(port), "--target", "localhost:" + str(self.target))
        self.assertTrue(again["reused"])
        self.assertEqual(again["id"], m["id"])
        code, _ = self.cli("edit", "echo", "--target", "bad:99999", check=False)
        self.assertEqual(code, 1)
        self.transfer(port)
        new = free_port()
        self.cli("edit", "echo", "--listen", str(new), "--rename", "renamed")
        self.assertFalse(reachable(port))
        self.transfer(new)
        code, _ = self.cli("stop", "echo", check=False)
        self.assertEqual(code, 1)

    def test_restore_enabled_but_not_stopped(self):
        p1, _ = self.add("active")
        p2, _ = self.add("paused")
        self.cli("stop", "paused")
        self.cli("daemon", "stop")
        self.assertFalse(reachable(p1))
        self.cli("daemon", "start")
        wait_for(lambda: reachable(p1))
        self.transfer(p1)
        self.assertFalse(reachable(p2))
        self.assertEqual({m["name"]: m["enabled"] for m in self.cli("list")["mappings"]}, {"active": True, "paused": False})

    def test_conflict_does_not_kill_external_listener_then_recovers(self):
        code, result = self.cli("add", "conflict", "--listen", str(self.target), "--target", "localhost:9", check=False)
        self.assertEqual(code, 2)
        self.assertIn(result["status"], ("retrying", "starting"))
        self.transfer(self.target, b"external listener survives")
        new = free_port()
        self.cli("edit", "conflict", "--listen", str(new), "--target", "localhost:" + str(self.target))
        self.transfer(new)
        self.cli("remove", "conflict")
        self.transfer(self.target)

    def test_target_errors_and_http_validation(self):
        httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), HTTP)
        self.addCleanup(httpd.server_close)
        self.addCleanup(httpd.shutdown)
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        port = free_port()
        self.cli("add", "web", "--listen", str(port), "--target", "localhost:" + str(httpd.server_port))
        result = self.cli("check", "web", "--http-path", "/health")
        self.assertTrue(result["ok"])
        self.assertEqual(result["http_status"], 401)
        self.cli("edit", "web", "--target", "localhost:" + str(free_port()))
        code, result = self.cli("check", "web", "--http-path", "/", check=False)
        self.assertEqual(code, 2)
        self.assertFalse(result["ok"])

    def test_private_control_api_and_concurrent_startup(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
            values = list(pool.map(lambda _: self.cli("daemon", "start"), range(5)))
        self.assertEqual(len({v["pid"] for v in values}), 1)
        rt = self.runtime()
        for headers, expected in (({}, 401), ({"Authorization": "Bearer " + rt["token"], "Origin": "https://evil.example"}, 403),
                                  ({"Authorization": "Bearer " + rt["token"], "Host": "evil.example"}, 403)):
            conn = http.client.HTTPConnection("127.0.0.1", rt["port"])
            conn.request("GET", "/api/mappings", headers=headers)
            self.assertEqual(conn.getresponse().status, expected)
            conn.close()
        self.assertEqual((self.home / "runtime.json").stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.home.stat().st_mode & 0o777, 0o700)

    def test_ipv6_loopback(self):
        try:
            port = free_port("::1")
        except OSError:
            self.skipTest("IPv6 loopback unavailable")
        self.cli("add", "v6", "--listen", "[::1]:" + str(port), "--target", "localhost:" + str(self.target))
        self.transfer(port, ip="::1")

    def test_active_connections_close_on_stop(self):
        port, _ = self.add()
        with socket.create_connection(("127.0.0.1", port), 3) as s:
            s.settimeout(3)
            s.sendall(b"unfinished")
            self.cli("stop", "echo")
            self.assertEqual(s.recv(1), b"")


@unittest.skipUnless(Path("/usr/sbin/sshd").exists(), "OpenSSH server is unavailable")
class RealSSHTests(LiveTests):
    # Only SSH-specific tests; TCP tests already run in LiveTests.
    def setUp(self):
        super().setUp()
        base = Path(self.tmp.name)
        self.ssh_port = free_port()
        self.user = getpass.getuser()
        for key in ("hostkey", "clientkey"):
            subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(base / key)], check=True, capture_output=True)
        self.ssh_config = base / "sshd_config"
        self.ssh_config.write_text("\n".join([
            "Port " + str(self.ssh_port), "ListenAddress 127.0.0.1", "HostKey " + str(base / "hostkey"),
            "PidFile " + str(base / "sshd.pid"), "AuthorizedKeysFile " + str(base / "clientkey.pub"),
            "StrictModes no", "PasswordAuthentication no", "KbdInteractiveAuthentication no", "UsePAM no",
            "PubkeyAuthentication yes", "AllowTcpForwarding yes", "GatewayPorts clientspecified", "UseDNS no",
            "LogLevel VERBOSE"]) + "\n")
        pub = (base / "hostkey.pub").read_text().split()
        known = base / "known_hosts"
        known.write_text("[127.0.0.1]:{} {} {}\n".format(self.ssh_port, pub[0], pub[1]))
        self.unwanted = free_port()
        client = base / "ssh_config"
        client.write_text("\n".join([
            "Host qa-alias", "  HostName 127.0.0.1", "  Port " + str(self.ssh_port), "  User " + self.user,
            "  IdentityFile " + str(base / "clientkey"), "  IdentitiesOnly yes", "  UserKnownHostsFile " + str(known),
            "  LocalForward {} 127.0.0.1:{}".format(self.unwanted, self.target),
            "  ControlMaster auto", "  ControlPersist yes", "  ControlPath " + str(base / "external-control")]) + "\n")
        bindir = base / "bin"
        bindir.mkdir()
        wrapper = bindir / "ssh"
        import shlex
        wrapper.write_text("#!/bin/sh\nexec /usr/bin/ssh -F " + shlex.quote(str(client)) + ' "$@"\n')
        wrapper.chmod(0o700)
        self.env["PATH"] = str(bindir) + os.pathsep + os.environ["PATH"]
        self.sshd = None
        self.launch_sshd()
        self.addCleanup(self.stop_sshd)

    def launch_sshd(self):
        with (Path(self.tmp.name) / "sshd.log").open("ab") as log:
            self.sshd = subprocess.Popen(["/usr/sbin/sshd", "-D", "-e", "-f", str(self.ssh_config)],
                                        stdout=subprocess.DEVNULL, stderr=log, start_new_session=True)
        try:
            wait_for(lambda: reachable(self.ssh_port), 4)
        except AssertionError:
            self.fail("Local sshd did not start: " + (Path(self.tmp.name) / "sshd.log").read_text())

    def stop_sshd(self):
        if self.sshd and self.sshd.poll() is None:
            # sshd keeps established sessions in separate groups; include only
            # descendants of this test-owned server when simulating a hard outage.
            rows = subprocess.check_output(["ps", "-axo", "pid=,ppid="], text=True)
            pairs = [tuple(map(int, line.split())) for line in rows.splitlines() if line.strip()]
            owned = {self.sshd.pid}
            while True:
                more = {pid for pid, ppid in pairs if ppid in owned}
                if more <= owned:
                    break
                owned |= more
            for pid in reversed(sorted(owned)):
                with contextlib.suppress(ProcessLookupError):
                    os.kill(pid, signal.SIGTERM)
            self.sshd.wait(timeout=5)

    def test_ssh_local_real_transfer_config_isolation_and_stop(self):
        port, m = self.add(via="qa-alias")
        self.assertEqual(m["status"], "running")
        self.transfer(port, os.urandom(200001))
        self.assertFalse(reachable(self.unwanted), "Inherited SSH LocalForward must not be created")
        self.assertFalse((Path(self.tmp.name) / "external-control").exists())
        r = self.cli("check", "echo")
        self.assertIsNone(r["target_tcp"], "Listener check must not claim SSH target verification")
        self.cli("stop", "echo")
        self.assertFalse(reachable(port))

    def test_ssh_reverse_real_transfer(self):
        port, _ = self.add(via="qa-alias", mode="ssh-remote")
        self.transfer(port, os.urandom(131077))
        result = self.cli("check", "echo")
        self.assertIsNone(result["listener_tcp"])
        self.assertTrue(result["target_tcp"])
        self.cli("remove", "echo")
        self.assertFalse(reachable(port))

    def test_ssh_forward_failure_preserves_external_listener(self):
        code, result = self.cli("add", "busy", "--via", "qa-alias", "--listen", str(self.target), "--target", "localhost:9", check=False)
        self.assertEqual(code, 2)
        self.transfer(self.target)
        self.cli("remove", "busy")
        self.transfer(self.target)

    def test_daemon_crash_releases_owned_ssh_forward(self):
        port, _ = self.add(via="qa-alias")
        self.transfer(port)
        os.kill(self.runtime()["pid"], signal.SIGKILL)
        wait_for(lambda: not reachable(port), 8)
        self.cli("daemon", "start")
        wait_for(lambda: reachable(port), 15)
        self.transfer(port)

    def test_ssh_reconnect_after_server_restart(self):
        port, _ = self.add(via="qa-alias")
        self.transfer(port)
        self.stop_sshd()
        wait_for(lambda: not reachable(port), 12)
        self.launch_sshd()
        wait_for(lambda: reachable(port), 20)
        self.transfer(port)


# Avoid rerunning inherited TCP cases with an unnecessary SSH fixture.
for _name in list(LiveTests.__dict__):
    if _name.startswith("test_"):
        setattr(RealSSHTests, _name, None)


if __name__ == "__main__":
    unittest.main(verbosity=2)
