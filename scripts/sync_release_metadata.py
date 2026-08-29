#!/usr/bin/env python3
"""Synchronize generated build metadata from release/metadata.json."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from deploy.animal_heroes_deploy.release_metadata import (  # noqa: E402
    MetadataError,
    ReleaseMetadata,
    check_checkout,
    sync_checkout,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail when generated files drift")
    arguments = parser.parse_args()
    try:
        metadata = ReleaseMetadata.load(ROOT / "release/metadata.json")
        if arguments.check:
            check_checkout(ROOT, metadata)
        else:
            sync_checkout(ROOT, metadata)
    except MetadataError as error:
        print(f"release metadata error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
