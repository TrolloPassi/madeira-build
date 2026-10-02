#!/usr/bin/env python3
"""Füllt die gestrippte ntdll.dll mit Nullen auf SizeOfImage + 0x50000 auf,
genau wie Madeiras build/wine-pe/build-ntdll.sh (der iOS-Loader braucht das)."""
import struct, sys
p = sys.argv[1]
d = open(p, 'rb').read()
pe = struct.unpack_from('<I', d, 0x3c)[0]
target = struct.unpack_from('<I', d, pe + 24 + 56)[0] + 0x50000
if len(d) > target:
    sys.exit(f"ntdll.dll ist {len(d)} Bytes, größer als Ziel {target}")
with open(p, 'ab') as f:
    f.write(b'\0' * (target - len(d)))
print(f"ntdll.dll: {len(d)} + {target - len(d)} = {target} Bytes")
