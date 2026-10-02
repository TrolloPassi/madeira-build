#!/usr/bin/env python3
"""Vergleicht zwei PE-Dateien Sektion für Sektion.

--expect-identical: Abbruch, wenn sich mehr unterscheidet als Zeitstempel
(Header) und Debug-Verzeichnis (.rdata, wenige Bytes). So wird geprüft, dass
der ungepatchte Neubau dem Original aus der IPA entspricht."""
import struct, sys

def load(path):
    d = open(path, 'rb').read()
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    ns = struct.unpack_from('<H', d, pe + 6)[0]
    so = struct.unpack_from('<H', d, pe + 20)[0]
    sh = pe + 24 + so
    secs = {}
    for i in range(ns):
        nm, vs, va, rs, ro = struct.unpack_from('<8sIIII', d, sh + 40 * i)
        secs[nm.rstrip(b'\0').decode()] = (vs, va, d[ro:ro + min(vs, rs)])
    soi = struct.unpack_from('<I', d, pe + 24 + 56)[0]
    return secs, soi

a, sa = load(sys.argv[1])
b, sb = load(sys.argv[2])
strict = '--expect-identical' in sys.argv
bad = sa != sb or list(a) != list(b)
print(f"SizeOfImage {sa:#x} / {sb:#x}")
for k in a:
    if k not in b:
        print(f"{k:10} fehlt im Neubau"); bad = True; continue
    (va_s, va, x), (vb_s, _, y) = a[k], b[k]
    n = sum(1 for i in range(min(len(x), len(y))) if x[i] != y[i]) + abs(len(x) - len(y))
    print(f"{k:10} size {va_s:#8x} / {vb_s:#8x}  abweichende Bytes {n}")
    if va_s != vb_s:
        bad = True
    if strict and n and not (k == '.rdata' and n <= 8):
        bad = True
if strict and bad:
    sys.exit("FEHLER: Neubau ohne Patches entspricht nicht dem Original")
if not strict and bad:
    sys.exit("FEHLER: Sektionsgrößen/Layout weichen ab")
print("ok")
