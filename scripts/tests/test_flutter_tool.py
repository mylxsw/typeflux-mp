"""Offline checks for Make's Flutter command routing. Never invokes Flutter."""

import argparse
from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "flutter_tool.py"
SPEC = importlib.util.spec_from_file_location("typeflux_flutter_tool", SCRIPT)
tool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tool)


def options(**overrides):
    values = {
        "environment": "dev",
        "platform": "auto",
        "device": "",
        "dry_run": False,
        "render_dir": None,
        "preview_font": None,
    }
    values.update(overrides)
    return argparse.Namespace(**values)


class ApiRoutingTests(unittest.TestCase):
    def test_shared_environment_presets_remain_distinct(self):
        for environment, expected in (
            ("dev", "https://typeflux-api.dev.fallout.in"),
            ("dev-nas", "http://nas-server.local:8080"),
            ("dev-macbook", "http://mac-pro.local:8080"),
            ("dev-macmini", "http://mac-mini.local:8080"),
            ("prod", "https://api.typeflux.app"),
        ):
            with self.subTest(environment=environment):
                origin, insecure = tool.api_configuration(
                    environment, "android", None, debug=True
                )
                self.assertEqual(origin, expected)
                self.assertEqual(insecure, environment in tool.LOCAL_HTTP_ENVIRONMENTS)

    def test_local_android_uses_host_alias_and_other_platforms_loopback(self):
        for platform, host in (
            ("android", "10.0.2.2"),
            ("ios", "127.0.0.1"),
            ("windows", "127.0.0.1"),
        ):
            with self.subTest(platform=platform):
                self.assertEqual(
                    tool.api_configuration("local", platform, None, debug=True),
                    (f"http://{host}:8080", True),
                )

    def test_explicit_https_origin_overrides_any_environment(self):
        for environment in ("local", *tool.PRESETS):
            with self.subTest(environment=environment):
                self.assertEqual(
                    tool.api_configuration(
                        environment, "android", "https://staging.example.com:8443/", False
                    ),
                    ("https://staging.example.com:8443", False),
                )

    def test_http_is_allowed_only_for_debug_local_networks(self):
        for host in (
            "localhost", "127.0.0.1", "10.0.2.2", "172.16.0.1",
            "172.31.255.254", "192.168.10.2", "169.254.1.2",
            "nas-server.local", "[::1]", "[fe80::1]", "[fd00::1]",
        ):
            for environment in tool.LOCAL_HTTP_ENVIRONMENTS:
                with self.subTest(host=host, environment=environment):
                    self.assertEqual(
                        tool.api_configuration(environment, "android", f"http://{host}:8080", True),
                        (f"http://{host}:8080", True),
                    )
        for environment, debug in (
            ("local", False), ("dev-nas", False), ("dev", True), ("prod", True),
        ):
            with self.subTest(environment=environment, debug=debug):
                with self.assertRaisesRegex(ValueError, "HTTP requires"):
                    tool.api_configuration(environment, "android", "http://192.168.1.2:8080", debug)

    def test_public_and_reserved_addresses_do_not_gain_insecure_access(self):
        for host in (
            "example.com", "localhost.example.com", "8.8.8.8", "172.15.255.255",
            "172.32.0.1", "192.0.2.1", "198.18.0.1", "100.64.0.1",
            "0.0.0.0", "[2001:4860:4860::8888]", "[::]",
        ):
            for environment in tool.LOCAL_HTTP_ENVIRONMENTS:
                with self.subTest(host=host, environment=environment):
                    with self.assertRaises(ValueError):
                        tool.api_configuration(environment, "android", f"http://{host}:8080", True)

    def test_origin_rejects_credentials_paths_queries_fragments_and_bad_ports(self):
        for origin in (
            "https://user:password@example.com", "https://example.com/api",
            "https://example.com?debug=true", "https://example.com#anchor",
            "https://example.com:0", "https://example.com:65536", "https://example.com:bad",
            "https://example.com /", "https://", "ftp://example.com", "file:///tmp/api",
        ):
            with self.subTest(origin=origin):
                with self.assertRaises(ValueError):
                    tool.api_configuration("prod", "android", origin, True)


class MakeTargetTests(unittest.TestCase):
    def test_mac_targets_forward_platform_and_device_to_launcher(self):
        with tempfile.TemporaryDirectory(prefix="typeflux-make-") as temporary:
            workspace = Path(temporary)
            (workspace / "Makefile").write_text((SCRIPT.parents[1] / "Makefile").read_text())
            recorder = workspace / "recorder.py"
            recorder.write_text('import json, sys\nprint(json.dumps(sys.argv[1:]))\n')
            for target in ("dev-macbook", "dev-macmini"):
                with self.subTest(target=target):
                    output = subprocess.check_output(
                        ["make", "--no-print-directory", target, "PLATFORM=ios", "DEVICE=fixture-device",
                         f'TOOL="{sys.executable}" "{recorder}"'],
                        cwd=workspace, text=True,
                    )
                    self.assertEqual(json.loads(output.splitlines()[-1]), [
                        "--environment", target, "--platform", "ios", "--device", "fixture-device",
                        "run", "--debug",
                    ])


class ToolEnvironmentTests(unittest.TestCase):
    def test_local_tools_are_discovered_without_overriding_explicit_environment(self):
        with tempfile.TemporaryDirectory(prefix="typeflux tools ") as temporary:
            workspace = Path(temporary)
            root = workspace / "codes" / "typeflux" / "typeflux-flutter"
            root.mkdir(parents=True)
            tools = workspace / ".tools"
            executable = "flutter.bat" if os.name == "nt" else "flutter"
            flutter = tools / "flutter-typeflux" / "bin" / executable
            flutter.parent.mkdir(parents=True)
            flutter.touch()
            (tools / "typeflux-android-sdk").mkdir()
            (tools / "typeflux-jdk/jdk-21.0.12.1+1/Contents/Home").mkdir(parents=True)
            original = {"PATH": "", "PUB_CACHE": "/explicit package cache", "JAVA_HOME": "/explicit jdk"}
            resolved, env = tool.tool_environment(original, root=root)
            self.assertEqual(resolved, str(flutter))
            self.assertEqual(env["PUB_CACHE"], "/explicit package cache")
            self.assertEqual(env["JAVA_HOME"], "/explicit jdk")
            self.assertEqual(env["ANDROID_HOME"], str(tools / "typeflux-android-sdk"))
            self.assertEqual(env["GRADLE_USER_HOME"], str(tools / "gradle"))
            self.assertEqual(env["FLUTTER_SUPPRESS_ANALYTICS"], "true")
            self.assertNotIn("ANDROID_HOME", original)

    def test_explicit_tools_and_flutter_paths_can_contain_spaces(self):
        with tempfile.TemporaryDirectory(prefix="typeflux overridden tools ") as temporary:
            configured = Path(temporary)
            explicit_flutter = str(configured / "custom flutter/bin/flutter")
            resolved, env = tool.tool_environment({
                "TYPEFLUX_TOOLS": str(configured), "FLUTTER": explicit_flutter,
                "ANDROID_HOME": "/custom android/sdk with spaces", "PATH": "",
            })
            self.assertEqual(resolved, explicit_flutter)
            self.assertEqual(env["PUB_CACHE"], str(configured / "pub-cache"))
            self.assertEqual(env["ANDROID_HOME"], "/custom android/sdk with spaces")

    def test_path_lookup_is_used_when_no_local_sdk_exists(self):
        with tempfile.TemporaryDirectory() as temporary:
            absent = str(Path(temporary) / "missing")
            with patch.object(tool.shutil, "which", return_value="/shared flutter/bin/flutter") as which:
                resolved, _ = tool.tool_environment({"TYPEFLUX_TOOLS": absent, "PATH": "/shared tools"})
            self.assertEqual(resolved, "/shared flutter/bin/flutter")
            which.assert_called_once_with("flutter.bat" if os.name == "nt" else "flutter", path="/shared tools")

    def test_missing_flutter_reports_an_actionable_error(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(tool.shutil, "which", return_value=None):
                with self.assertRaisesRegex(ValueError, "Flutter not found"):
                    tool.tool_environment({"TYPEFLUX_TOOLS": str(Path(temporary) / "missing"), "PATH": ""})


class DeviceAndCommandTests(unittest.TestCase):
    devices = [
        {"id": "emulator-5554", "targetPlatform": "android-arm64", "isSupported": True},
        {"id": "ios-simulator", "targetPlatform": "ios", "isSupported": True},
        {"id": "unsupported", "targetPlatform": "android-x64", "isSupported": False},
        {"id": "chrome", "targetPlatform": "web-javascript", "isSupported": True},
    ]

    def test_selects_only_one_supported_device_for_requested_platform(self):
        self.assertEqual(tool.select_device(self.devices, "android"), "emulator-5554")
        self.assertEqual(tool.select_device(self.devices, "ios"), "ios-simulator")

    def test_no_devices_explains_how_to_connect_one_without_prompting(self):
        with patch("builtins.input") as prompt:
            with self.assertRaisesRegex(ValueError, "No connected android devices"):
                tool.select_device([], "android")
        prompt.assert_not_called()

    def test_multiple_devices_are_listed_and_selection_continues_launch(self):
        devices = [*self.devices,
                   {"id": "ios-phone", "name": "My iPhone", "targetPlatform": "ios", "emulator": False}]
        devices[1] = dict(devices[1], name="iPhone Simulator", emulator=True)
        output = io.StringIO()
        with patch.object(tool.subprocess, "check_output", return_value=json.dumps(devices)), \
                patch.object(tool.sys.stdin, "isatty", return_value=True), \
                patch("builtins.input", return_value="2") as prompt, redirect_stdout(output):
            command, origin = tool.prepare_command(
                options(platform="ios", environment="dev-macbook"), ["run", "--debug"], "/sdk/flutter", {},
            )
        prompt.assert_called_once()
        self.assertEqual(command[-2:], ["-d", "ios-phone"])
        self.assertEqual(origin, "http://mac-pro.local:8080")
        self.assertIn("[1] iPhone Simulator (simulator)", output.getvalue())
        self.assertIn("[2] My iPhone (physical device)", output.getvalue())
        self.assertNotIn("emulator-5554", output.getvalue())
        self.assertNotIn("unsupported", output.getvalue())
        self.assertNotIn("chrome", output.getvalue())

    def test_invalid_device_input_prompts_again(self):
        devices = [self.devices[0], {"id": "phone", "targetPlatform": "android-arm64"}]
        with patch.object(tool.sys.stdin, "isatty", return_value=True), \
                patch("builtins.input", side_effect=["", "text", "0", "3", " 2 "]) as prompt, \
                redirect_stdout(io.StringIO()):
            self.assertEqual(tool.select_device(devices, "android"), "phone")
        self.assertEqual(prompt.call_count, 5)

    def test_noninteractive_multiple_devices_lists_ids_without_reading_input(self):
        devices = [self.devices[0], {"id": "phone", "targetPlatform": "android-arm64"}]
        output = io.StringIO()
        with patch.object(tool.sys.stdin, "isatty", return_value=False), \
                patch("builtins.input") as prompt, redirect_stdout(output):
            with self.assertRaisesRegex(ValueError, "Set DEVICE=<id>"):
                tool.select_device(devices, "android")
        prompt.assert_not_called()
        self.assertIn("emulator-5554", output.getvalue())
        self.assertIn("phone", output.getvalue())

    def test_cancelled_selection_never_launches_flutter(self):
        devices = [self.devices[0], {"id": "phone", "targetPlatform": "android-arm64"}]
        for response in ("q", "Q", EOFError(), KeyboardInterrupt()):
            with self.subTest(response=response), \
                    patch.object(tool.sys, "argv", [str(SCRIPT), "--platform", "android", "run", "--debug"]), \
                    patch.object(tool, "tool_environment", return_value=("/sdk/flutter", {})), \
                    patch.object(tool.subprocess, "check_output", return_value=json.dumps(devices)), \
                    patch.object(tool.sys.stdin, "isatty", return_value=True), \
                    patch("builtins.input", side_effect=[response]), \
                    patch.object(tool.subprocess, "call") as launch, \
                    redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(tool.main(), 130 if isinstance(response, KeyboardInterrupt) else 1)
                launch.assert_not_called()

    def test_android_run_queries_devices_without_shell_and_adds_selected_id(self):
        env = {"PATH": "/tools with spaces"}
        flutter = "/Flutter SDK/bin/flutter"
        with patch.object(tool.subprocess, "check_output", return_value=json.dumps(self.devices)) as query:
            command, origin = tool.prepare_command(options(platform="android"), ["run", "--debug"], flutter, env)
        query.assert_called_once_with([flutter, "devices", "--machine"], env=env, cwd=tool.ROOT, text=True)
        self.assertEqual(command[-2:], ["-d", "emulator-5554"])
        self.assertEqual(origin, tool.PRESETS["dev"])

    def test_explicit_device_skips_discovery_and_preserves_the_identifier(self):
        with patch.object(tool.subprocess, "check_output") as query:
            command, _ = tool.prepare_command(options(platform="android", device="test device with spaces"),
                                              ["run", "--debug"], "/sdk/flutter", {})
        query.assert_not_called()
        self.assertEqual(command[-2:], ["-d", "test device with spaces"])

    def test_dev_auto_keeps_flutter_device_selection(self):
        with patch.object(tool.subprocess, "check_output") as query:
            command, origin = tool.prepare_command(options(), ["run", "--debug"], "/sdk/flutter", {})
        query.assert_not_called()
        self.assertNotIn("-d", command)
        self.assertEqual(origin, tool.PRESETS["dev"])

    def test_local_auto_requires_explicit_routing_or_api_override(self):
        with patch.object(tool.subprocess, "check_output") as query:
            with self.assertRaisesRegex(ValueError, "PLATFORM"):
                tool.prepare_command(options(environment="local"), ["run", "--debug"], "/sdk/flutter", {})
            command, origin = tool.prepare_command(options(environment="local"), ["run", "--debug"],
                                                   "/sdk/flutter", {"API_URL": "http://192.168.1.2:8080"})
        query.assert_not_called()
        self.assertEqual(origin, "http://192.168.1.2:8080")
        self.assertIn("--dart-define=TYPEFLUX_ALLOW_INSECURE_HTTP=true", command)

    def test_apk_target_routes_local_http_to_android_without_device_probe(self):
        with patch.object(tool.subprocess, "check_output") as query:
            command, origin = tool.prepare_command(options(environment="local", platform="ios"),
                                                   ["build", "apk", "--debug"], "/sdk/flutter", {})
        query.assert_not_called()
        self.assertEqual(origin, "http://10.0.2.2:8080")
        self.assertNotIn("-d", command)

    def test_build_rejects_missing_or_conflicting_modes(self):
        for mode_args in ([], ["--debug", "--profile"], ["--profile", "--release"], ["--debug", "--profile", "--release"]):
            with self.subTest(mode_args=mode_args):
                with self.assertRaisesRegex(ValueError, "exactly one mode"):
                    tool.prepare_command(options(), ["build", "apk", *mode_args], "/sdk/flutter", {})

    def test_profile_and_release_local_http_cannot_silently_build(self):
        for environment in tool.LOCAL_HTTP_ENVIRONMENTS:
            for mode in ("profile", "release"):
                with self.subTest(environment=environment, mode=mode):
                    with self.assertRaisesRegex(ValueError, "HTTP requires"):
                        tool.prepare_command(options(environment=environment), ["build", "apk", f"--{mode}"], "/sdk/flutter", {})

    def test_mac_environments_support_auto_and_explicit_platforms(self):
        for environment, host in (("dev-macbook", "mac-pro.local"), ("dev-macmini", "mac-mini.local")):
            for platform in ("auto", "android", "ios", "windows"):
                with self.subTest(environment=environment, platform=platform):
                    command, origin = tool.prepare_command(
                        options(environment=environment, platform=platform, dry_run=True),
                        ["run", "--debug"], "/sdk/flutter", {},
                    )
                    self.assertEqual(origin, f"http://{host}:8080")
                    self.assertIn(f"--dart-define=TYPEFLUX_API_URL={origin}", command)
                    self.assertIn("--dart-define=TYPEFLUX_ALLOW_INSECURE_HTTP=true", command)

    def test_mac_environment_presets_allow_lan_ip_overrides(self):
        for environment in ("dev-macbook", "dev-macmini"):
            with self.subTest(environment=environment):
                command, origin = tool.prepare_command(
                    options(environment=environment), ["run", "--debug"], "/sdk/flutter",
                    {"API_URL": "http://192.168.1.2:8080"},
                )
                self.assertEqual(origin, "http://192.168.1.2:8080")
                self.assertIn("--dart-define=TYPEFLUX_ALLOW_INSECURE_HTTP=true", command)

    def test_extra_flags_cannot_replace_environment_defines(self):
        for extra in ("--dart-define=TYPEFLUX_API_URL=https://other.example", "--dart-define=TYPEFLUX_ALLOW_INSECURE_HTTP=true", "--dart-define-from-file=local.json"):
            with self.subTest(extra=extra):
                with self.assertRaisesRegex(ValueError, "Use API_URL and ENV"):
                    tool.prepare_command(options(), ["run", "--debug", extra], "/sdk/flutter", {})

    def test_host_checks_fail_before_launch_but_dry_run_can_describe_other_hosts(self):
        for platform, host in (("windows", "darwin"), ("ios", "linux")):
            with self.subTest(platform=platform), patch.object(tool.sys, "platform", host):
                with self.assertRaisesRegex(ValueError, "requires"):
                    tool.prepare_command(options(platform=platform), ["run", "--debug"], "/sdk/flutter", {})
                with patch.object(tool.subprocess, "check_output") as query:
                    command, _ = tool.prepare_command(options(platform=platform, dry_run=True), ["run", "--debug"], "/sdk/flutter", {})
                query.assert_not_called()
                self.assertIn("-d", command)

    def test_arguments_with_spaces_and_shell_metacharacters_stay_single_arguments(self):
        arguments = ["test", "test/path with spaces.dart", "--name", "case $(echo should-not-run); echo `no`"]
        command, origin = tool.prepare_command(options(), arguments, "/Flutter SDK/bin/flutter", {})
        self.assertEqual(command, ["/Flutter SDK/bin/flutter", *arguments])
        self.assertEqual(arguments, ["test", "test/path with spaces.dart", "--name", "case $(echo should-not-run); echo `no`"])
        self.assertIsNone(origin)

    def test_dart_and_emulator_commands_keep_space_containing_paths_intact(self):
        with tempfile.TemporaryDirectory(prefix="Dart SDK ") as temporary:
            flutter = Path(temporary) / "bin" / "flutter"
            with patch.object(tool.shutil, "which", return_value=None):
                command, _ = tool.prepare_command(options(), ["dart", "format", "lib/file with spaces.dart"], str(flutter), {})
            self.assertEqual(command, [str(flutter.resolve().with_name("dart.bat" if os.name == "nt" else "dart")), "format", "lib/file with spaces.dart"])
            command, _ = tool.prepare_command(options(), ["launch-emulator", "Pixel device"], str(flutter), {})
            self.assertEqual(command, [str(flutter), "emulators", "--launch", "Pixel device"])
        with self.assertRaisesRegex(ValueError, "EMULATOR"):
            tool.prepare_command(options(), ["launch-emulator", ""], "/sdk/flutter", {})


class MainExecutionTests(unittest.TestCase):
    def test_main_passes_argv_list_directly_to_subprocess(self):
        flutter = "/SDK with spaces/flutter"
        environment = {"PATH": "/custom tools"}
        args = ["test", "test/a file.dart", "--name", "literal $(touch sentinel); `whoami`"]
        with patch.object(tool.sys, "argv", [str(SCRIPT), *args]), \
                patch.object(tool, "tool_environment", return_value=(flutter, environment)), \
                patch.object(tool.subprocess, "call", return_value=7) as call:
            self.assertEqual(tool.main(), 7)
        call.assert_called_once_with([flutter, *args], cwd=tool.ROOT, env=environment)
        self.assertNotIn("shell", call.call_args.kwargs)

    def test_default_main_environment_is_dev_and_dry_run_never_starts_flutter(self):
        output = io.StringIO()
        with patch.object(tool.sys, "argv", [str(SCRIPT), "--dry-run", "run", "--debug"]), \
                patch.object(tool, "tool_environment", return_value=("/SDK/flutter", {})), \
                patch.object(tool.subprocess, "call") as call, redirect_stdout(output):
            self.assertEqual(tool.main(), 0)
        call.assert_not_called()
        payload = json.loads(output.getvalue())
        self.assertEqual(payload["environment"], "dev")
        self.assertEqual(payload["api"], tool.PRESETS["dev"])

    def test_invalid_mode_returns_one_and_does_not_launch(self):
        error = io.StringIO()
        with patch.object(tool.sys, "argv", [str(SCRIPT), "run", "--debug", "--release"]), \
                patch.object(tool, "tool_environment", return_value=("/SDK/flutter", {})), \
                patch.object(tool.subprocess, "call") as call, redirect_stderr(error):
            self.assertEqual(tool.main(), 1)
        call.assert_not_called()
        self.assertIn("exactly one mode", error.getvalue())


if __name__ == "__main__":
    unittest.main()
