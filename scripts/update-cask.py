#!/usr/bin/env python3
"""Pin the cask to an explicitly chosen public release ZIP and SHA-256."""

import argparse
import os
from pathlib import Path
import re
import tempfile

from release import configuration


def render_cask(template: str, version: str, checksum: str) -> str:
    configuration(version, "production")
    if not re.fullmatch(r"[0-9a-fA-F]{64}", checksum) or checksum == "0" * 64:
        raise ValueError("Use the actual release ZIP's 64-character SHA-256, not a placeholder.")
    if template.count("@VERSION@") != 1 or template.count("@SHA256@") != 1:
        raise ValueError("The cask template must contain exactly one version and checksum placeholder.")
    return template.replace("@VERSION@", version).replace("@SHA256@", checksum.lower())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="Release version without the v prefix")
    parser.add_argument("sha256", help="SHA-256 of EyeSaver-VERSION-arm64.zip")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    output = root / "Casks/eye-saver.rb"
    try:
        content = render_cask((root / "Casks/eye-saver.rb.in").read_text(), args.version, args.sha256)
    except ValueError as error:
        parser.error(str(error))
    with tempfile.NamedTemporaryFile(mode="w", dir=output.parent, encoding="utf-8", delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(content)
    try:
        temporary.chmod(0o644)
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Pinned eye-saver cask to v{args.version}; verify the public ZIP before committing.")


if __name__ == "__main__":
    main()
