#!/usr/bin/env python3
"""Validate, package and publish an explicitly requested release."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


def configuration(version, mode):
    match = re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?", version)
    if not match or any(part.isdigit() and len(part) > 1 and part[0] == "0" for part in (match[4] or "").split(".")):
        raise ValueError("Use major.minor.patch with an optional SemVer prerelease suffix; build metadata is not supported.")
    if mode not in ("production", "development-preview"):
        raise ValueError("Unknown signing mode.")
    if mode == "development-preview" and not match[4]:
        raise ValueError("A development preview requires a prerelease version, such as 1.0.0-beta.1.")
    return {"version": version, "tag": f"v{version}", "app_version": ".".join(match.groups()[:3]),
            "signing_mode": mode, "prerelease": bool(match[4]), "asset": f"EyeSaver-{version}-arm64.zip"}


def command(*args, cwd=None):
    return subprocess.check_output(args, text=True, cwd=cwd).strip()


def resolve_ref(ref):
    if not ref or len(ref) > 256 or ref.startswith("-") or any(ord(char) < 32 for char in ref):
        raise ValueError("Invalid source ref.")
    for candidate in (ref, f"refs/remotes/origin/{ref}", f"refs/tags/{ref}"):
        result = subprocess.run(["git", "rev-parse", "--verify", "--end-of-options", f"{candidate}^{{commit}}"], capture_output=True, text=True)
        if result.returncode == 0 and re.fullmatch(r"[0-9a-f]{40}", result.stdout.strip()):
            return result.stdout.strip()
    raise ValueError("The source ref does not resolve to a fetched commit.")


def check_tag(tag, commit):
    result = subprocess.run(["git", "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}"], capture_output=True, text=True)
    if result.returncode == 0 and result.stdout.strip() != commit:
        raise ValueError("The release tag already points to another commit; it will not be moved.")


def check_versions(app, app_version, build_number):
    for bundle in (app, app / "Contents/PlugIns/EyeSaverControl.appex"):
        with (bundle / "Contents/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        if info.get("CFBundleShortVersionString") != app_version or info.get("CFBundleVersion") != build_number:
            raise ValueError(f"Release version/build number does not match {bundle.name}.")


def signing_policy(mode, environment):
    required = ["BUILD_CERTIFICATE_BASE64", "P12_PASSWORD", "KEYCHAIN_PASSWORD", "SIGNING_IDENTITY", "DEVELOPMENT_TEAM"]
    if mode == "production":
        required += ["NOTARY_KEY_BASE64", "NOTARY_KEY_ID", "NOTARY_ISSUER_ID"]
        prefix = "Developer ID Application:"
    elif mode == "development-preview":
        prefix = "Apple Development:"
    else:
        raise ValueError("Unknown signing mode.")
    if any(not environment.get(name) for name in required):
        raise ValueError("Required signing credentials are missing. Production also requires notarization credentials; no test-signing fallback is allowed.")
    if not environment["SIGNING_IDENTITY"].startswith(prefix):
        raise ValueError(f"The selected release mode requires a {prefix} identity; no substitution is allowed.")


def package(version, mode, commit, build_number):
    result = configuration(version, mode)
    if not re.fullmatch(r"[0-9a-f]{40}", commit) or resolve_ref("HEAD") != commit:
        raise ValueError("Package HEAD must equal the selected source commit.")
    if not re.fullmatch(r"[1-9]\d*", build_number):
        raise ValueError("The build number must be a positive integer.")
    build = Path(os.environ.get("BUILD_DIR", ".build-app")).resolve()
    app = build / "Build/Products/Release/EyeSaver.app"
    check_versions(app, result["app_version"], build_number)
    prefix = "Developer ID Application:" if mode == "production" else "Apple Development:"
    teams = set()
    for binary in (app, app / "Contents/PlugIns/EyeSaverControl.appex", app / "Contents/MacOS/ddc-key"):
        info = subprocess.check_output(["codesign", "-dvvv", str(binary)], stderr=subprocess.STDOUT, text=True)
        if f"Authority={prefix}" not in info or "Timestamp=" not in info:
            raise ValueError("Every executable must have the requested Apple identity and a secure timestamp; no ad-hoc fallback is allowed.")
        teams.add(re.search(r"^TeamIdentifier=(.+)$", info, re.MULTILINE)[1])
    if len(teams) != 1 or "not set" in teams:
        raise ValueError("All executable signatures must belong to the same Apple team.")
    if mode == "production":
        subprocess.run(["xcrun", "stapler", "validate", str(app)], check=True)
        subprocess.run(["spctl", "--assess", "--type", "execute", str(app)], check=True)
    subprocess.run(["./scripts/package.sh", "signed"], check=True)
    artifacts = build / "artifacts"
    archive = artifacts / result["asset"]
    if archive.exists():
        raise ValueError("The versioned archive already exists; use a clean build directory.")
    (artifacts / "EyeSaver-signed.zip").rename(archive)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (artifacts / f"{archive.name}.sha256").write_text(f"{digest}  {archive.name}\n")
    result.update(commit=commit, build_number=build_number, sha256=digest)
    (artifacts / "release.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


def remote_commit(repo, tag):
    result = subprocess.run(["gh", "api", f"repos/{repo}/git/ref/tags/{tag}"], capture_output=True, text=True)
    if result.returncode:
        if "HTTP 404" in result.stderr:
            return None
        raise ValueError("Unable to inspect the remote release tag.")
    target = json.loads(result.stdout)["object"]
    for _ in range(10):
        if target["type"] == "commit":
            return target["sha"]
        if target["type"] != "tag":
            break
        target = json.loads(command("gh", "api", f"repos/{repo}/git/tags/{target['sha']}"))["object"]
    raise ValueError("The remote tag does not resolve to a commit.")


def publish(metadata_path, draft):
    data = json.loads(metadata_path.read_text())
    expected = configuration(data["version"], data["signing_mode"])
    if any(data.get(key) != value for key, value in expected.items()) or not re.fullmatch(r"[0-9a-f]{40}", data["commit"]):
        raise ValueError("Invalid release metadata.")
    root = metadata_path.parent
    archive = root / data["asset"]
    checksum = root / f"{archive.name}.sha256"
    if hashlib.sha256(archive.read_bytes()).hexdigest() != data["sha256"] or checksum.read_text() != f"{data['sha256']}  {archive.name}\n":
        raise ValueError("Release artifact checksum mismatch.")
    repo = os.environ["GITHUB_REPOSITORY"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise ValueError("Invalid repository.")
    tag = data["tag"]
    existing = subprocess.run(["gh", "release", "view", tag, "--repo", repo], capture_output=True)
    if existing.returncode == 0:
        raise ValueError("A release with this version already exists; assets will not be overwritten.")
    target = remote_commit(repo, tag)
    if target is None:
        created = subprocess.run(["gh", "api", "--method", "POST", f"repos/{repo}/git/refs", "-f", f"ref=refs/tags/{tag}", "-f", f"sha={data['commit']}"], capture_output=True)
        if created.returncode and remote_commit(repo, tag) != data["commit"]:
            raise ValueError("Unable to create the release tag at the selected source commit.")
    elif target != data["commit"]:
        raise ValueError("The remote tag points to another commit; it will not be moved.")
    preview = data["signing_mode"] == "development-preview"
    notes = ("Development preview signed with Apple Development; not notarized. This is a test build, not a Developer ID distribution. Control Center acceptance on other Macs is not guaranteed.\n\n"
             if preview else "Signed with Developer ID Application and notarized by Apple.\n\n")
    notes += f"Apple Silicon · macOS 27+ · Samsung S27B80P / ViewFinity S80PB\n\nSource commit: `{data['commit']}`\n\nSHA-256: `{data['sha256']}`\n"
    with tempfile.TemporaryDirectory(prefix="eyesaver-release-") as temporary:
        notes_path = Path(temporary) / "notes.md"
        notes_path.write_text(notes)
        arguments = ["gh", "release", "create", tag, str(archive), str(checksum), "--repo", repo,
                     "--verify-tag", "--target", data["commit"], "--title", f"Eye Saver {data['version']}", "--notes-file", str(notes_path), "--draft"]
        if data["prerelease"]:
            arguments += ["--prerelease", "--latest=false"]
        subprocess.run(arguments, check=True)
        downloaded = Path(temporary) / "downloaded"
        subprocess.run(["gh", "release", "download", tag, "--repo", repo, "--dir", str(downloaded), "--pattern", archive.name, "--pattern", checksum.name], check=True)
        if hashlib.sha256((downloaded / archive.name).read_bytes()).hexdigest() != data["sha256"] or (downloaded / checksum.name).read_bytes() != checksum.read_bytes():
            raise ValueError("Uploaded assets failed download verification; release remains a draft.")
    if remote_commit(repo, tag) != data["commit"]:
        raise ValueError("Release tag changed unexpectedly; release remains a draft.")
    if not draft:
        subprocess.run(["gh", "release", "edit", tag, "--repo", repo, "--draft=false", f"--latest={'false' if data['prerelease'] else 'true'}"], check=True)
    url = command("gh", "release", "view", tag, "--repo", repo, "--json", "url", "--jq", ".url")
    print(url)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as stream:
            stream.write(f"[Eye Saver {data['version']}]({url}) · {'draft' if draft else 'published'} · {data['signing_mode']}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    validate = sub.add_parser("validate")
    validate.add_argument("version")
    validate.add_argument("mode")
    validate.add_argument("source_ref")
    policy = sub.add_parser("signing-policy")
    policy.add_argument("mode")
    archive = sub.add_parser("package")
    for name in ("version", "mode", "commit", "build_number"):
        archive.add_argument(name)
    upload = sub.add_parser("publish")
    upload.add_argument("metadata", type=Path)
    upload.add_argument("--draft", choices=("true", "false"), required=True)
    args = parser.parse_args()
    if args.command == "validate":
        data = configuration(args.version, args.mode)
        data["commit"] = resolve_ref(args.source_ref)
        check_tag(data["tag"], data["commit"])
        print(json.dumps(data, indent=2))
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
                for key in ("commit", "app_version", "tag", "asset"):
                    stream.write(f"{key}={data[key]}\n")
    elif args.command == "signing-policy":
        signing_policy(args.mode, os.environ)
        print("Requested signing policy satisfied.")
    elif args.command == "package":
        package(args.version, args.mode, args.commit, args.build_number)
    else:
        publish(args.metadata, args.draft == "true")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Release failed: {error}")
