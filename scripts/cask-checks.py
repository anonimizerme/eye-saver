#!/usr/bin/env python3
"""Check cask pins and migration failure handling without changing installed apps."""

import importlib.util
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("update_cask", ROOT / "scripts/update-cask.py")
UPDATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(UPDATE)
TEMPLATE = (ROOT / "Casks/eye-saver.rb.in").read_text()


class CaskChecks(unittest.TestCase):
    def test_pin_and_rejections(self):
        rendered = UPDATE.render_cask(TEMPLATE, "1.0.0-beta.1", "a" * 64)
        self.assertIn('version "1.0.0-beta.1"', rendered)
        self.assertIn('sha256 "' + "a" * 64 + '"', rendered)
        self.assertNotIn("@VERSION@", rendered)
        self.assertIn("/releases/download/v#{version}/EyeSaver-#{version}-arm64.zip", rendered)
        for version in ["v1.0.0", "1.0", "1.0.0/../../main", "1.0.0\n", "01.0.0"]:
            with self.assertRaises(ValueError): UPDATE.render_cask(TEMPLATE, version, "a" * 64)
        for checksum in ["", "0" * 64, "a" * 63, "g" * 64, "a" * 64 + "\n"]:
            with self.assertRaises(ValueError): UPDATE.render_cask(TEMPLATE, "1.0.0", checksum)

    def test_hook_order_and_guards(self):
        self.assertIn("depends_on arch: :arm64", TEMPLATE)
        self.assertIn("depends_on macos: :golden_gate", TEMPLATE)
        self.assertIn('app "EyeSaver.app", target: app_path', TEMPLATE)
        self.assertNotIn("--no-quarantine", TEMPLATE)
        self.assertNotIn("xattr", TEMPLATE)
        self.assertNotIn("/usr/bin/pluginkit", TEMPLATE)
        self.assertNotIn("network_access:", TEMPLATE)
        self.assertIn("uninstall_preflight_steps", TEMPLATE)
        self.assertNotIn("uninstall_postflight", TEMPLATE)
        hooks = re.findall(r"<<~'SHELL'.*?\n(.*?)\n\s*SHELL", TEMPLATE, re.S)
        self.assertEqual(len(hooks), 3)
        for hook in hooks:
            subprocess.run(["/bin/bash", "-n"], input=hook, text=True, check=True)
        self.assertIn('pgrep -u "$(/usr/bin/id -u)" -x ddc-key', hooks[0])
        self.assertIn('pgrep -u "$(/usr/bin/id -u)" -x ddc-key', hooks[2])
        self.assertIn('lsregister -f -R -trusted "$1"', hooks[1])
        self.assertNotIn("lsregister -u", hooks[1])
        self.assertIn('lsregister -u "$1"', hooks[2])

    def test_postflight_registers_only_after_signature_validation(self):
        hook = re.findall(r"<<~'SHELL'.*?\n(.*?)\n\s*SHELL", TEMPLATE, re.S)[1]
        with tempfile.TemporaryDirectory(prefix="eyesaver-cask-register-") as temporary:
            directory = Path(temporary)
            codesign = directory / "codesign"
            codesign.write_text('#!/bin/bash\nexit "$EYESAVER_CHECK_SIGNATURE_STATUS"\n')
            codesign.chmod(0o755)
            register = directory / "lsregister"
            register.write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$EYESAVER_CHECK_REGISTER_LOG"\n')
            register.chmod(0o755)
            command_log = directory / "registration"
            copied = hook.replace("/usr/bin/codesign", str(codesign)).replace(
                "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                str(register))
            environment = {**os.environ, "EYESAVER_CHECK_SIGNATURE_STATUS": "1",
                           "EYESAVER_CHECK_REGISTER_LOG": str(command_log)}
            app = str(directory / "Applications/EyeSaver.app")
            command = ["/bin/bash", "-c", copied, "cask-postflight", app]
            result = subprocess.run(command, env=environment, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(command_log.exists())
            environment["EYESAVER_CHECK_SIGNATURE_STATUS"] = "0"
            result = subprocess.run(command, env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(command_log.read_text().splitlines(), ["-f", "-R", "-trusted", app])

    def test_migration_failure_restores_original(self):
        self.migration_failure("install")

    def test_failed_cask_trust_preserves_original(self):
        self.migration_failure("trust")

    def migration_failure(self, phase):
        with tempfile.TemporaryDirectory(prefix="eyesaver-migration-") as temporary:
            directory = Path(temporary)
            home = directory / "home"
            app = home / "Applications/EyeSaver.app"
            (app / "Contents").mkdir(parents=True)
            (app / "original").write_text("preserve me")
            commands = directory / "commands"
            commands.mkdir()
            fixtures = {
                "brew": '''#!/bin/bash
printf '%s\\n' "$*" >> "$EYESAVER_CHECK_COMMAND_LOG"
case "$1" in
  list) exit 1;;
  tap) exit 0;;
  trust)
    [[ "$*" == 'trust --cask anonimizerme/eye-saver/eye-saver' ]] || exit 77
    [[ "$EYESAVER_CHECK_FAILURE" != trust ]] || exit 8;;
  install) exit 9;;
  *) exit 1;;
esac
''',
                "PlistBuddy": '#!/bin/bash\necho local.eyesaver.app\n',
                "codesign": '#!/bin/bash\nif [[ "$1" == -dvv ]]; then echo "Authority=Apple Development: Test"; fi\n',
                "pgrep": '#!/bin/bash\nexit 1\n',
                "pkill": '#!/bin/bash\nexit 0\n',
                "lsregister": '#!/bin/bash\nexit 0\n',
                "pluginkit": '#!/bin/bash\nexit 0\n',
            }
            for name, content in fixtures.items():
                path = commands / name
                path.write_text(content)
                path.chmod(0o755)
            script = (ROOT / "scripts/migrate-to-brew.sh").read_text()
            script = script.replace("$HOME", "${EYESAVER_CHECK_HOME}")
            replacements = {
                "/usr/libexec/PlistBuddy": str(commands / "PlistBuddy"),
                "/usr/bin/codesign": str(commands / "codesign"),
                "/usr/bin/pgrep": str(commands / "pgrep"),
                "/usr/bin/pkill": str(commands / "pkill"),
                "/usr/bin/pluginkit": str(commands / "pluginkit"),
                "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister": str(commands / "lsregister"),
                "system_app=/Applications/EyeSaver.app": f"system_app={directory}/absent-system-app",
            }
            for source, target in replacements.items(): script = script.replace(source, target)
            copy = directory / "migrate.sh"
            copy.write_text(script)
            command_log = directory / "command-log"
            environment = {**os.environ, "EYESAVER_CHECK_HOME": str(home),
                           "EYESAVER_CHECK_FAILURE": phase, "EYESAVER_CHECK_COMMAND_LOG": str(command_log),
                           "PATH": str(commands) + os.pathsep + os.environ["PATH"]}
            result = subprocess.run(["/bin/bash", str(copy)], env=environment, text=True, capture_output=True)
            self.assertEqual(result.returncode, 8 if phase == "trust" else 9, result.stderr)
            self.assertEqual((app / "original").read_text(), "preserve me")
            calls = command_log.read_text().splitlines()
            self.assertEqual([call for call in calls if call.startswith("trust")],
                             ["trust --cask anonimizerme/eye-saver/eye-saver"])
            if phase == "trust":
                self.assertFalse(any(call.startswith("install") for call in calls))
                self.assertFalse((home / "Library/Application Support/EyeSaver/Manual Backups").exists())
            else:
                self.assertIn("original manual app was restored", result.stderr)
            self.assertFalse(list(home.glob("Library/Application Support/EyeSaver/Manual Backups/*/bundle")))

    def test_preflight_refuses_existing_app_and_active_command(self):
        hook = re.findall(r"<<~'SHELL'.*?\n(.*?)\n\s*SHELL", TEMPLATE, re.S)[0]
        with tempfile.TemporaryDirectory(prefix="eyesaver-cask-guard-") as temporary:
            root = Path(temporary)
            target = root / "EyeSaver.app"
            target.mkdir()
            (target / "original").write_text("preserve me")
            pgrep = root / "pgrep"
            pgrep.write_text("#!/bin/bash\nexit 1\n")
            pgrep.chmod(0o755)
            copied = hook.replace("/usr/bin/pgrep", str(pgrep)).replace("/Applications/EyeSaver.app", str(root / "absent-system-app"))
            result = subprocess.run(["/bin/bash", "-c", copied, "cask-preflight", str(target), str(root / "unread-staged-app")], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must be migrated", result.stderr)
            self.assertEqual((target / "original").read_text(), "preserve me")
            pgrep.write_text("#!/bin/bash\nexit 0\n")
            result = subprocess.run(["/bin/bash", "-c", copied, "cask-preflight", str(root / "new-target"), str(root / "unread-staged-app")], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("active monitor command", result.stderr)


if __name__ == "__main__":
    unittest.main()
