"""Read and write the HUD records in FFXIV's per-character ADDON.DAT.

Record layout (32 bytes) follows FFXIVClientStructs AddonConfigEntry:
hash = CRC32 of "<addon name>_a", then x, y, scale (floats), flags (u32), width, height (u16),
four bytes, four bytes of padding.
"""
import struct
import zlib

REC = struct.Struct("<IfffIHH4s4s")
DEFAULT_START, DEFAULT_COUNT_AT = 0x70, 0x60
LAYOUT_STARTS = (0x29E0, 0x3820, 0x4660, 0x54A0)
LAYOUT_HEADER, LAYOUT_COUNT = 0x40, 112


def name_hash(name):
    return zlib.crc32((name + "_a").encode())


def blocks(data):
    count = struct.unpack_from("<I", data, DEFAULT_COUNT_AT)[0]
    yield "default", DEFAULT_START, count
    for i, start in enumerate(LAYOUT_STARTS):
        yield f"layout{i + 1}", start + LAYOUT_HEADER, LAYOUT_COUNT


def records(data, start, count):
    for i in range(count):
        off = start + i * REC.size
        yield off, REC.unpack_from(data, off)
