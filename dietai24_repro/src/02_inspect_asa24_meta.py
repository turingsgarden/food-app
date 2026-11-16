from pathlib import Path
import pandas as pd

pd.set_option("display.max_colwidth", None)
pd.set_option("display.width", 250)

f = Path("data/asa24/ASA24_ImageMetadata.xlsx")
xl = pd.ExcelFile(f)
print("sheets:", xl.sheet_names)
for s in xl.sheet_names:
    df = pd.read_excel(f, sheet_name=s, header=None)
    print("=" * 70)
    print(s, df.shape)
    print(df.head(60 if s.lower() == "readme" else 6).to_string())

print("=" * 70)
print("first 5 png files:")
for p in sorted(Path("data/asa24").rglob("*.png"))[:5]:
    print(p)
