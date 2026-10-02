#!/usr/bin/env python3
"""Prüft, dass jede Datei eine x64-PE-Datei mit Authenticode-Signatur ist."""
import struct, sys
bad = 0
for path in sys.argv[1:]:
    d = open(path, 'rb').read()
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    if struct.unpack_from('<H', d, pe + 4)[0] != 0x8664:
        print('NICHT x64 ', path); bad += 1; continue
    off, size = struct.unpack_from('<II', d, pe + 24 + 112 + 4 * 8)
    ok = size and off + size <= len(d)
    bad += not ok
    print(('signiert  ' if ok else 'UNSIGNIERT'), path)
sys.exit(bad)
