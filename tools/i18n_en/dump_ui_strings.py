"""Liste les chaines UI candidates (copy joueur) des scripts client.

Heuristique : chaine avec espace, ou tout-majuscules >=3, ou caractere
accentue. Les commentaires sont exclus. Sert d'inventaire pour la bascule
UI anglaise R32 et de base a la gate anti-francais.
"""

from __future__ import annotations

import io
import re
import sys
from pathlib import Path

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

ACCENTS = "\u00e0\u00e2\u00e4\u00e9\u00e8\u00ea\u00eb\u00ee\u00ef\u00f4\u00f6\u00f9\u00fb\u00fc\u00e7"
UPPER = "A-Z\u00c0\u00c2\u00c9\u00c8\u00ca\u00cb\u00ce\u00cf\u00d4\u00d6\u00d9\u00db\u00dc\u00c7"


def is_candidate(text: str) -> bool:
    if not re.search(r"[A-Za-z]", text):
        return False
    if re.search(f"[{ACCENTS}]", text, re.IGNORECASE):
        return True
    if " " in text.strip():
        return True
    return bool(re.fullmatch(f"[{UPPER}0-9\\.\\!\\?\u2026\\+%:,()\\-']{{3,}}", text))


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "client")
    count = 0
    for path in sorted(root.rglob("*.gd")):
        if "tests" in path.parts:
            continue
        for num, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            code = re.sub(r"(^|\s)#.*$", "", line)
            for chunk in re.findall(r'"([^"]+)"', code):
                if is_candidate(chunk):
                    count += 1
                    print(f"{path.as_posix()}:{num}: {chunk}")
    print(f"TOTAL: {count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
