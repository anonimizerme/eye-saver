#!/usr/bin/env python3
"""Pin the cask to an explicitly chosen public release ZIP and SHA-256."""

import argparse
import hashlib
import os
from pathlib import Path
import re
import tempfile
from urllib.request import urlopen

from release import configuration


def render_cask(template: str, version: str, checksum: str) -> str:
    configuration(version, "production")
    if not re.fullmatch(r"[0-9a-fA-F]{64}", checksum) or checksum == "0" * 64:
        raise ValueError("Use the actual release ZIP's 64-character SHA-256, not a placeholder.")
    if template.count("@VERSION@") != 1 or template.count("@SHA256@") != 1:
        raise ValueError("The cask template must contain exactly one version and checksum placeholder.")
    return template.replace("@VERSION@", version).replace("@SHA256@", checksum.lower())


def version_order(version):
    base, _, prerelease = version.partition("-")
    identifiers = tuple((0, int(part)) if part.isdigit() else (1, part)
                        for part in (prerelease.split(".") if prerelease else ()))
    return tuple(map(int, base.split("."))), not prerelease, identifiers


def verified_checksum(release):
    asset = release["asset"]
    url = f"https://github.com/anonimizerme/eye-saver/releases/download/{release['tag']}/{asset}"
    with urlopen(f"{url}.sha256", timeout=30) as response:
        checksum = response.read(256).decode("ascii")
    expected = re.fullmatch(r"([0-9a-fA-F]{64})  " + re.escape(asset) + r"\n?", checksum)
    if not expected:
        raise ValueError(f"The published checksum must name {asset}.")

    digest = hashlib.sha256()
    with urlopen(url, timeout=30) as response:
        while chunk := response.read(1024 * 1024):
            digest.update(chunk)
    if digest.hexdigest() != expected[1].lower():
        raise ValueError(f"SHA-256 mismatch for the published {asset}.")
    return digest.hexdigest()


def update_cask(root, version, checksum):
    output = root / "Casks/eye-saver.rb"
    current = output.read_text() if output.exists() else ""
    if checksum is None:
        release = configuration(version, "production")
        pinned = re.search(r'^  version "([^"]+)"$', current, re.MULTILINE)
        if not pinned:
            raise ValueError("Could not read the current cask version.")
        if version_order(version) < version_order(pinned[1]):
            print(f"v{version} is older than the cask's v{pinned[1]}; skipping update.")
            return
        checksum = verified_checksum(release)
        print(f"Verified public ZIP for v{version} against its published SHA-256.")

    content = render_cask((root / "Casks/eye-saver.rb.in").read_text(), version, checksum)
    if content == current:
        print(f"The cask already pins v{version} with this checksum.")
        return
    with tempfile.NamedTemporaryFile(mode="w", dir=output.parent, encoding="utf-8", delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(content)
    try:
        temporary.chmod(0o644)
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Pinned eye-saver cask to v{version}.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="Release version without the v prefix")
    parser.add_argument("sha256", nargs="?", help="SHA-256 of the release ZIP (verify against GitHub if omitted)")
    args = parser.parse_args()
    try:
        update_cask(Path(__file__).resolve().parent.parent, args.version, args.sha256)
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
