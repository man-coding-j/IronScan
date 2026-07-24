from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]


def package_sha256(package: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(item for item in package.rglob("*") if item.is_file()):
        digest.update(path.relative_to(package).as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise TypeError(f"Expected object in {path}")
    return value


def main() -> None:
    checksum_lines = (ROOT / "Models" / "Checksums" / "SHA256SUMS").read_text(encoding="utf-8").splitlines()
    locked_checksums = {path: digest for digest, path in (line.split(maxsplit=1) for line in checksum_lines)}
    pairs = (
        ("segmentation_manifest.json", "TongueSegmentation.mlpackage"),
        ("risk_manifest.json", "AnemiaRisk.mlpackage"),
        ("pallor_manifest.json", "IronScanPallorClassifier.mlpackage"),
        ("multi_screen_manifest.json", "IronScanMultiScreen.mlpackage"),
        ("eye_manifest.json", "IronScanEye.mlpackage"),
        ("eye_clinical_manifest.json", "IronScanEye_Clinical.mlpackage"),
        ("nail_manifest.json", "IronScanNail.mlpackage"),
        ("tongue_manifest.json", "IronScanTongue.mlpackage"),
    )
    for manifest_name, package_name in pairs:
        manifest = load_json(ROOT / "Models" / "Manifests" / manifest_name)
        actual = package_sha256(ROOT / "Models" / "CoreML" / package_name)
        if manifest.get("sha256") != actual:
            raise SystemExit(f"Checksum mismatch for {package_name}")
        if locked_checksums.get(f"CoreML/{package_name}") != actual:
            raise SystemExit(f"SHA256SUMS mismatch for {package_name}")
    print("Model package checksums match manifests.")


if __name__ == "__main__":
    main()
