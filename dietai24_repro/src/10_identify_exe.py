import re
from pathlib import Path

b = Path("FNDDS/full/FNDDS_2019-2020_SAS.EXE").read_bytes()
print("size:", len(b), "bytes")

sigs = {
    "7z signature": b"7z\xbc\xaf\x27\x1c",
    "zip local header": b"PK\x03\x04",
    "zip end record": b"PK\x05\x06",
    "rar": b"Rar!",
    "cab": b"MSCF",
}
for name, s in sigs.items():
    idx = [m.start() for m in re.finditer(re.escape(s), b)]
    print(f"{name:18s} count={len(idx):4d} first offsets={idx[:5]}")

print()
for key in [b"7-Zip", b"WinZip", b"Inno Setup", b"Nullsoft", b"InstallShield",
            b"PKWARE", b"Self-Extract", b"WinRAR", b"IExpress", b"Cabinet", b"sas7bdat"]:
    print(f"{key.decode():14s} found: {key in b}")
