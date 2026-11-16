from pathlib import Path
import pandas as pd

root = Path("FNDDS")
wanted = ["Foods and Beverages", "Portions and Weights", "FNDDS Nutrient Values"]

for f in sorted(root.glob("*.xlsx")):
    if not any(w in f.name for w in wanted):
        continue
    print("=" * 80)
    print(f.name)
    xl = pd.ExcelFile(f)
    print("sheets:", xl.sheet_names)
    for sheet in xl.sheet_names:
        full = xl.parse(sheet, header=None)
        print(f"\n--- sheet {sheet!r}, raw shape {full.shape} ---")
        print(full.iloc[:4, :12].to_string(max_colwidth=30))
