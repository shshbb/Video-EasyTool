from __future__ import annotations

import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "assets" / "AppIcon.iconset"
OUTPUT = ROOT / "assets" / "AppIcon.icns"


# Include both classic and retina chunk variants because Finder is stricter
# than the runtime dock/menu icon path when parsing icon families.
ENTRIES: list[tuple[str, str]] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
]


def pack_chunk(kind: bytes, payload: bytes) -> bytes:
    return kind + struct.pack(">I", len(payload) + 8) + payload


def main() -> None:
    chunks: list[bytes] = []
    toc_entries: list[bytes] = []

    for kind, filename in ENTRIES:
        payload = (ICONSET / filename).read_bytes()
        chunk = pack_chunk(kind.encode("ascii"), payload)
        chunks.append(chunk)
        toc_entries.append(kind.encode("ascii") + struct.pack(">I", len(payload) + 8))

    toc_chunk = pack_chunk(b"TOC ", b"".join(toc_entries))
    body = toc_chunk + b"".join(chunks)
    OUTPUT.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


if __name__ == "__main__":
    main()
