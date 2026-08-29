#!/usr/bin/env python3
"""CLI entry: parse dual-tablet smoke evidence into performance metrics."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from deploy.animal_heroes_deploy.smoke_results import main

if __name__ == "__main__":
    sys.exit(main())
