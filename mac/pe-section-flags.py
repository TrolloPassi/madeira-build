#!/usr/bin/env python3
"""Set the Characteristics of one section of a PE file in place.

usage: pe-section-flags.py FILE SECTION FLAGS   (FLAGS e.g. 0xe0000060)
"""
import struct
import sys

path, want, flags = sys.argv[1], sys.argv[2].encode(), int(sys.argv[3], 0)
d = bytearray(open(path, 'rb').read())
pe = struct.unpack_from('<I', d, 0x3c)[0]
count = struct.unpack_from('<H', d, pe + 6)[0]
o = pe + 24 + struct.unpack_from('<H', d, pe + 20)[0]
for _ in range(count):
    if d[o:o + 8].rstrip(b'\0') == want:
        old = struct.unpack_from('<I', d, o + 36)[0]
        struct.pack_into('<I', d, o + 36, flags)
        open(path, 'wb').write(d)
        print(f"{path}: {want.decode()} {old:#010x} -> {flags:#010x}")
        break
    o += 40
else:
    sys.exit(f"{path}: no section {want.decode()}")
