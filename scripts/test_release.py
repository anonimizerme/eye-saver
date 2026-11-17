#!/usr/bin/env python3
"""Software-only checks for release validation and version identity."""
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release", Path(__file__).with_name("release.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseChecks(unittest.TestCase):
    def test_version_and_preview_policy(self):
        data = release.configuration("1.0.0-beta.1", "development-preview")
        self.assertEqual((data["app_version"], data["tag"], data["asset"]),
                         ("1.0.0", "v1.0.0-beta.1", "EyeSaver-1.0.0-beta.1-arm64.zip"))
        self.assertTrue(data["prerelease"])
        self.assertFalse(release.configuration("1.2.3", "production")["prerelease"])
        for version in ("v1.0.0", "1.0", "01.0.0", "1.0.0+build", "1.0.0-01", "1.0.0-beta.01", "1.0.0\n", "1.0.0/../../bad"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                release.configuration(version, "production")
        with self.assertRaises(ValueError):
            release.configuration("1.0.0", "development-preview")

    def test_production_never_uses_development_or_missing_credentials(self):
        credentials = {name: "fixture" for name in ["BUILD_CERTIFICATE_BASE64", "P12_PASSWORD", "KEYCHAIN_PASSWORD", "DEVELOPMENT_TEAM", "NOTARY_KEY_BASE64", "NOTARY_KEY_ID", "NOTARY_ISSUER_ID"]}
        credentials["SIGNING_IDENTITY"] = "Apple Development: Fixture"
        release.signing_policy("development-preview", credentials)
        with self.assertRaises(ValueError):
            release.signing_policy("production", credentials)
        credentials["SIGNING_IDENTITY"] = "Developer ID Application: Fixture"
        release.signing_policy("production", credentials)
        del credentials["NOTARY_KEY_BASE64"]
        with self.assertRaises(ValueError):
            release.signing_policy("production", credentials)
        credentials["SIGNING_IDENTITY"] = "-"
        with self.assertRaises(ValueError):
            release.signing_policy("development-preview", credentials)

    def test_app_and_extension_versions_must_match(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "EyeSaver.app"
            extension = app / "Contents/PlugIns/EyeSaverControl.appex"
            for bundle in (app, extension):
                (bundle / "Contents").mkdir(parents=True)
                (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "101"}))
            release.check_versions(app, "1.0.0", "101")
            (extension / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.0", "CFBundleVersion": "101"}))
            with self.assertRaises(ValueError):
                release.check_versions(app, "1.0.0", "101")

    def test_ref_validation_and_tag_immutability(self):
        sha = "a" * 40
        with patch.object(release.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, sha + "\n", "")):
            self.assertEqual(release.resolve_ref("main"), sha)
            release.check_tag("v1.0.0", sha)
            with self.assertRaises(ValueError):
                release.check_tag("v1.0.0", "b" * 40)
        for ref in ("", "--help", "main\nother", "x" * 257):
            with self.subTest(ref=ref), self.assertRaises(ValueError):
                release.resolve_ref(ref)
        with patch.object(release.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "missing")):
            with self.assertRaises(ValueError):
                release.resolve_ref("does-not-exist")

    def test_existing_release_and_conflicting_tag_are_not_overwritten(self):
        import hashlib
        import json
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            metadata = release.configuration("1.0.0-beta.1", "development-preview")
            metadata.update(commit="a" * 40, build_number="101", sha256=hashlib.sha256(b"fixture").hexdigest())
            (root / metadata["asset"]).write_bytes(b"fixture")
            (root / (metadata["asset"] + ".sha256")).write_text(f"{metadata['sha256']}  {metadata['asset']}\n")
            file = root / "release.json"
            file.write_text(json.dumps(metadata))
            with patch.dict(release.os.environ, {"GITHUB_REPOSITORY": "fixture/repo"}), patch.object(release.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run:
                with self.assertRaises(ValueError):
                    release.publish(file, False)
                self.assertEqual(run.call_count, 1)
            with patch.dict(release.os.environ, {"GITHUB_REPOSITORY": "fixture/repo"}), patch.object(release.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)) as run, patch.object(release, "remote_commit", return_value="b" * 40):
                with self.assertRaises(ValueError):
                    release.publish(file, False)
                self.assertEqual(run.call_count, 1, "A conflicting tag must prevent tag writes and release creation")
            calls = []

            def corrupt_download(arguments, **kwargs):
                calls.append(arguments)
                if arguments[:3] == ["gh", "release", "download"]:
                    destination = Path(arguments[arguments.index("--dir") + 1])
                    destination.mkdir()
                    (destination / metadata["asset"]).write_bytes(b"corrupt")
                    (destination / (metadata["asset"] + ".sha256")).write_text("corrupt")
                return subprocess.CompletedProcess(arguments, 1 if arguments[:3] == ["gh", "release", "view"] else 0)

            with patch.dict(release.os.environ, {"GITHUB_REPOSITORY": "fixture/repo"}), patch.object(release.subprocess, "run", side_effect=corrupt_download), patch.object(release, "remote_commit", return_value=metadata["commit"]):
                with self.assertRaises(ValueError):
                    release.publish(file, False)
            self.assertFalse(any(arguments[:3] == ["gh", "release", "edit"] for arguments in calls), "Failed asset verification must leave the release as a draft")


if __name__ == "__main__":
    unittest.main()
