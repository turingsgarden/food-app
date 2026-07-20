import base64
import json
import mimetypes
import sys
from pathlib import Path

if len(sys.argv) < 2:
    print("Usage: python3 make_ocr_payload.py <image_path>")
    raise SystemExit(1)

image_path = Path(sys.argv[1])

if not image_path.exists():
    print(f"Image not found: {image_path}")
    raise SystemExit(1)

mime_type = mimetypes.guess_type(image_path.name)[0] or "image/jpeg"

with image_path.open("rb") as image_file:
    encoded = base64.b64encode(image_file.read()).decode("utf-8")

payload = {
    "image_base64": encoded,
    "filename": image_path.name,
    "mime_type": mime_type,
}

output_path = Path("/tmp/ocr_payload.json")

with output_path.open("w") as output_file:
    json.dump(payload, output_file)

print(f"Payload created: {output_path}")
print(f"Image: {image_path.name}")
print(f"Base64 characters: {len(encoded)}")