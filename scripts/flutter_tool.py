#!/usr/bin/env python3
"""Portable Flutter launcher for Make targets; requires only Python's stdlib."""

import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from urllib.parse import urlsplit
import zipfile


ROOT = Path(__file__).resolve().parents[1]
PRESETS = {
    "dev": "https://typeflux-api.dev.fallout.in",
    "dev-nas": "http://nas-server.local:8080",
    "dev-macbook": "http://mac-pro.local:8080",
    "dev-macmini": "http://mac-mini.local:8080",
    "prod": "https://api.typeflux.app",
}
LOCAL_HTTP_ENVIRONMENTS = ("local", "dev-nas", "dev-macbook", "dev-macmini")


def tool_environment(environ, root=ROOT):
    env = dict(environ)
    configured = env.get("TYPEFLUX_TOOLS")
    tools = Path(configured).expanduser() if configured else root.parents[2] / ".tools"
    if tools.is_dir():
        defaults = {
            "PUB_CACHE": tools / "pub-cache",
            "GRADLE_USER_HOME": tools / "gradle",
            "ANDROID_USER_HOME": tools / "typeflux-android-userhome",
            "ANALYZER_STATE_LOCATION_OVERRIDE": tools / "analyzer",
            "XDG_CONFIG_HOME": tools / "config",
        }
        for name, value in defaults.items():
            env.setdefault(name, str(value))
        sdk = tools / "typeflux-android-sdk"
        if sdk.is_dir():
            env.setdefault("ANDROID_HOME", str(sdk))
        jdk = tools / "typeflux-jdk/jdk-21.0.12.1+1/Contents/Home"
        if jdk.is_dir():
            env.setdefault("JAVA_HOME", str(jdk))
    env.setdefault("FLUTTER_SUPPRESS_ANALYTICS", "true")
    executable = "flutter.bat" if os.name == "nt" else "flutter"
    flutter = env.get("FLUTTER")
    if not flutter:
        local = tools / "flutter-typeflux/bin" / executable
        flutter = str(local) if local.is_file() else shutil.which(executable, path=env.get("PATH"))
    if not flutter:
        raise ValueError("Flutter not found. Install Flutter 3.47.2 or set FLUTTER in Makefile.local.")
    return flutter, env


def local_host(host):
    if host == "localhost" or host.endswith(".local"):
        return True
    try:
        ip = ipaddress.ip_address(host)
        # Restrict development HTTP to loopback, link-local and RFC1918 networks.
        return ip.is_loopback or ip.is_link_local or any(
            ip in ipaddress.ip_network(network)
            for network in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fc00::/7")
            if ip.version == ipaddress.ip_network(network).version
        )
    except ValueError:
        return False


def api_configuration(environment, platform, override, debug):
    origin = override or PRESETS.get(environment)
    if origin is None:
        host = "10.0.2.2" if platform == "android" else "127.0.0.1"
        origin = f"http://{host}:8080"
    url = urlsplit(origin)
    try:
        port = url.port
    except ValueError:
        raise ValueError("API_URL has an invalid port.") from None
    if (url.scheme not in ("https", "http") or not url.hostname
            or url.username is not None or url.password is not None
            or url.path not in ("", "/") or url.query or url.fragment
            or any(c.isspace() for c in origin) or (port is not None and port == 0)):
        raise ValueError("API_URL must be an HTTP(S) origin without credentials, path, query or fragment.")
    insecure = url.scheme == "http"
    if insecure and not (debug and environment in LOCAL_HTTP_ENVIRONMENTS and local_host(url.hostname)):
        raise ValueError("HTTP requires ENV=local, dev-nas, dev-macbook or dev-macmini, debug mode and a local-network address. Use HTTPS otherwise.")
    return origin.rstrip("/"), insecure


def select_device(devices, platform):
    candidates = [d for d in devices if d.get("isSupported", True) and (
        d.get("targetPlatform", "").startswith("android") if platform == "android"
        else d.get("targetPlatform") == "ios"
    )]
    if not candidates:
        raise ValueError(f"No connected {platform} devices found. "
                         "Connect a device or start a simulator with make emulators/emulator.")
    if len(candidates) == 1:
        return candidates[0]["id"]

    print(f"Available {platform} devices:", flush=True)
    for number, device in enumerate(candidates, start=1):
        kind = ("simulator" if platform == "ios" else "emulator") if device.get("emulator") else "physical device"
        print(f"  [{number}] {device.get('name') or device['id']} ({kind}) — {device['id']}", flush=True)
    if not sys.stdin.isatty():
        raise ValueError("Multiple devices found without an interactive terminal. "
                         "Set DEVICE=<id> using one of the devices listed above.")

    while True:
        try:
            choice = input(f"Select a device [1-{len(candidates)}] (q to cancel): ").strip()
        except EOFError:
            raise ValueError("Device selection cancelled.") from None
        if choice.lower() == "q":
            raise ValueError("Device selection cancelled.")
        if choice.isascii() and choice.isdecimal() and 1 <= int(choice) <= len(candidates):
            return candidates[int(choice) - 1]["id"]
        print(f"Enter a number from 1 to {len(candidates)}, or q to cancel.", flush=True)


def prepare_command(options, args, flutter, env):
    if not args:
        raise ValueError("A Flutter command is required; run make help.")
    args = list(args)
    if args[0] == "dart":
        dart_name = "dart.bat" if os.name == "nt" else "dart"
        flutter_path = Path(shutil.which(flutter, path=env.get("PATH")) or flutter).resolve()
        return [str(flutter_path.with_name(dart_name)), *args[1:]], None
    if args[0] == "launch-emulator":
        if len(args) != 2 or not args[1]:
            raise ValueError("Set EMULATOR=<id> from make emulators.")
        return [flutter, "emulators", "--launch", args[1]], None
    origin = None
    if args[0] in ("run", "build"):
        if any("TYPEFLUX_API_URL" in arg or "TYPEFLUX_ALLOW_INSECURE_HTTP" in arg
               or arg.startswith("--dart-define-from-file") for arg in args):
            raise ValueError("Use API_URL and ENV instead of overriding environment dart-defines in extra arguments.")
        modes = [mode for mode in ("debug", "profile", "release") if f"--{mode}" in args]
        if len(modes) != 1:
            raise ValueError("Select exactly one mode: debug, profile or release.")
        platform = options.platform
        if args[:2] == ["build", "apk"] or args[:2] == ["build", "appbundle"]:
            platform = "android"
        elif args[0] == "build" and len(args) > 1 and args[1] in ("ios", "windows"):
            platform = args[1]
        if platform == "windows" and sys.platform != "win32" and not options.dry_run:
            raise ValueError("Windows run/build requires a Windows host with Visual Studio C++ tools.")
        if platform == "ios" and sys.platform != "darwin" and not options.dry_run:
            raise ValueError("iOS run/build requires macOS with Xcode.")
        if options.environment == "local" and platform == "auto" and not env.get("API_URL"):
            raise ValueError("For local API routing set PLATFORM=android/ios/windows, or set API_URL explicitly.")
        origin, insecure = api_configuration(options.environment, platform, env.get("API_URL"), modes[0] == "debug")
        args += [f"--dart-define=TYPEFLUX_API_URL={origin}",
                 f"--dart-define=TYPEFLUX_ALLOW_INSECURE_HTTP={str(insecure).lower()}"]
        if args[0] == "run":
            device = options.device or ("windows" if platform == "windows" else None)
            if not device and platform in ("android", "ios"):
                if options.dry_run:
                    device = f"<connected-{platform}-device>"
                else:
                    output = subprocess.check_output([flutter, "devices", "--machine"], env=env, cwd=ROOT, text=True)
                    device = select_device(json.loads(output), platform)
            if device:
                args += ["-d", device]
    return [flutter, *args], origin


def verify_apk(path, env):
    apk = Path(path)
    with zipfile.ZipFile(apk) as contents:
        if contents.testzip() is not None:
            raise ValueError("APK ZIP integrity check failed.")
        abis = {name.split("/")[1] for name in contents.namelist() if name.startswith("lib/")}
        if abis != {"arm64-v8a"}:
            raise ValueError(f"Expected ARM64-only APK; found {sorted(abis)}")
    sdk = env.get("ANDROID_HOME") or env.get("ANDROID_SDK_ROOT")
    if not sdk:
        raise ValueError("Set ANDROID_HOME to verify the APK signature and metadata.")
    build_tools = Path(sdk) / "build-tools"
    versions = sorted((p for p in build_tools.iterdir() if p.is_dir()),
                      key=lambda p: tuple(int(part) if part.isdigit() else 0 for part in p.name.split(".")))
    if not versions:
        raise ValueError("No Android SDK build-tools found.")
    latest = versions[-1]
    signer = latest / ("apksigner.bat" if os.name == "nt" else "apksigner")
    aapt = latest / ("aapt.exe" if os.name == "nt" else "aapt")
    subprocess.run([str(signer), "verify", "--verbose", str(apk)], env=env, check=True)
    metadata = subprocess.check_output([str(aapt), "dump", "badging", str(apk)], env=env, text=True)
    for line in metadata.splitlines():
        if line.startswith(("package:", "sdkVersion:", "targetSdkVersion:", "native-code:")):
            print(line)
    print(f"Bytes: {apk.stat().st_size}\nSHA-256: {hashlib.sha256(apk.read_bytes()).hexdigest()}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", choices=("local", *PRESETS), default="dev")
    parser.add_argument("--platform", choices=("auto", "android", "ios", "windows"), default="auto")
    parser.add_argument("--device", default="")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--render-dir")
    parser.add_argument("--preview-font")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    try:
        flutter, env = tool_environment(os.environ)
        if options.command and options.command[0] == "verify-apk":
            if len(options.command) != 2:
                raise ValueError("verify-apk requires one APK path.")
            verify_apk(options.command[1], env)
            return 0
        command, origin = prepare_command(options, options.command, flutter, env)
        if options.preview_font:
            font = Path(options.preview_font).expanduser().resolve()
            if not font.is_file():
                raise ValueError("PREVIEW_FONT does not point to a font file.")
            env["TYPEFLUX_PREVIEW_FONT"] = str(font)
        if options.render_dir:
            destination = Path(options.render_dir).expanduser().resolve()
            if not options.dry_run:
                destination.mkdir(parents=True, exist_ok=True)
            env["TYPEFLUX_RENDER_DIR"] = str(destination)
        if options.dry_run:
            print(json.dumps({"environment": options.environment, "api": origin, "command": command,
                              "tools": {k: env.get(k) for k in ("JAVA_HOME", "ANDROID_HOME", "PUB_CACHE", "GRADLE_USER_HOME")}}, indent=2))
            return 0
        if origin:
            print(f"Typeflux {options.environment}: {origin}", flush=True)
        return subprocess.call(command, cwd=ROOT, env=env)
    except KeyboardInterrupt:
        print("\nDevice selection or launch interrupted.", file=sys.stderr)
        return 130
    except (ValueError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f"Typeflux tooling: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
