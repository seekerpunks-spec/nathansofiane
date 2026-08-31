"""Restaure les WebP district : délègue au pipeline netteté (alpha lissé)."""
from pathlib import Path
import runpy

runpy.run_path(str(Path(__file__).with_name("polish_visuals.py")))
