"""Exercise the evaluated session setup and OpenSSH agent fallback."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AgentConfigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get("SSH_AGENT_CONFIG"):
            cls.config = json.loads(Path(os.environ["SSH_AGENT_CONFIG"]).read_text())
            return
        expression = '''let
          host = (builtins.getFlake "%s").nixosConfigurations.nixos.config;
        in {
          session = host.environment.etc."xdg/uwsm/env.d/ssh-agent.sh".text or "";
          shell = host.environment.extraInit;
          zsh = host.programs.zsh.shellInit;
          ssh = host.programs.ssh.extraConfig;
        }''' % ROOT
        cls.config = json.loads(subprocess.check_output(
            ["nix", "eval", "--offline", "--impure", "--json", "--expr", expression],
            text=True,
        ))

    def test_session_publishes_socket_before_compositor_start(self):
        self.assertTrue(self.config["session"], "Missing UWSM agent environment setup")
        env = os.environ.copy()
        env.pop("SSH_AUTH_SOCK", None)
        env["XDG_RUNTIME_DIR"] = "/run/user/1234"
        output = subprocess.check_output(
            ["sh", "-c", self.config["session"] + '\nprintf "%s" "$SSH_AUTH_SOCK"'],
            env=env, text=True,
        )
        self.assertEqual(output, "/run/user/1234/gcr/ssh")

    def test_new_shell_recovers_missing_socket(self):
        env = os.environ.copy()
        env.pop("SSH_AUTH_SOCK", None)
        env["XDG_RUNTIME_DIR"] = "/run/user/1234"
        output = subprocess.check_output(
            ["sh", "-c", self.config["shell"] + '\nprintf "%s" "$SSH_AUTH_SOCK"'],
            env=env, text=True,
        )
        self.assertEqual(output, "/run/user/1234/gcr/ssh")

    def test_session_preserves_custom_agent(self):
        env = os.environ.copy()
        env.update(SSH_AUTH_SOCK="/custom/agent", XDG_RUNTIME_DIR="/run/user/1234")
        for script in [self.config["session"], self.config["shell"]]:
            output = subprocess.check_output(
                ["sh", "-c", script + '\nprintf "%s" "$SSH_AUTH_SOCK"'],
                env=env, text=True,
            )
            self.assertEqual(output, "/custom/agent")

    def test_zsh_recovers_socket_with_inherited_nixos_environment_guard(self):
        env = os.environ.copy()
        env.pop("SSH_AUTH_SOCK", None)
        env.update(XDG_RUNTIME_DIR="/run/user/1234", __NIXOS_SET_ENVIRONMENT_DONE="1")
        output = subprocess.check_output(
            ["sh", "-c", self.config["zsh"] + '\nprintf "%s" "$SSH_AUTH_SOCK"'],
            env=env, text=True,
        )
        self.assertEqual(output, "/run/user/1234/gcr/ssh")

    def test_all_hosts_reuse_connections_until_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "ssh_config"
            config.write_text(self.config["ssh"])
            for host in ["github.com", "ssh.github.com", "example.org"]:
                output = subprocess.check_output(
                    ["ssh", "-G", "-F", str(config), "git@" + host],
                    text=True, stderr=subprocess.DEVNULL,
                )
                settings = dict(line.split(" ", 1) for line in output.splitlines())
                self.assertEqual(settings["controlmaster"], "auto")
                self.assertEqual(settings["controlpersist"], "yes")
                self.assertTrue(settings["controlpath"].startswith(
                    f"/run/user/{os.getuid()}/ssh-session-"))

    def test_ssh_fallback_only_when_socket_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "ssh_config"
            config.write_text(self.config["ssh"])
            for socket in [None, "/custom/agent"]:
                env = os.environ.copy()
                env.pop("SSH_AUTH_SOCK", None)
                if socket is not None:
                    env["SSH_AUTH_SOCK"] = socket
                output = subprocess.check_output(
                    ["ssh", "-G", "-F", str(config), "git@github.com"],
                    env=env, text=True, stderr=subprocess.DEVNULL,
                )
                agent = [line for line in output.splitlines() if line.startswith("identityagent ")]
                expected = [f"identityagent /run/user/{os.getuid()}/gcr/ssh"] if socket is None else []
                self.assertEqual(agent, expected)


if __name__ == "__main__":
    unittest.main()
