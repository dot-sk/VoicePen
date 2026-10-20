"""Prepare two immutable GigaAM model assets and an offline publication plan."""
import argparse
import hashlib
import json
import re
import subprocess
import zipfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("assets", type=Path)
parser.add_argument("--repository", default="dot-sk/VoicePen")
parser.add_argument("--tag", default="model-assets-gigaam-600m-f16-v1")
args = parser.parse_args()
if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repository) or not re.fullmatch(r"model-assets-gigaam-600m-f16-v[1-9][0-9]*", args.tag):
    raise ValueError("Invalid repository or GigaAM-only immutable tag")
root = args.assets.resolve()
native_path = root / "native-package-manifest.json"
if hashlib.sha256(native_path.read_bytes()).hexdigest() != "7738da1d56246941906071a4177dd5586dd02c5560df4d97eb6fee72b52626e8":
    raise ValueError("Unexpected canonical native package manifest")
native = json.loads(native_path.read_text())
entry = json.loads((root / "model-manifest-entry.json").read_text())
model = root / "gigaam-600m-F16.gguf"
expected = "06b1224edb7eb9b9b797c5d25539b6aa852e6a069fbfdce706760a3135e26cae"
if model.stat().st_size != 1_172_222_176 or entry["sha256"] != expected or native["model"]["gguf_sha256"] != expected:
    raise ValueError("Unexpected model identity")
if entry["runtimePackageID"] != native["candidate"] or entry["downloadURL"] is not None:
    raise ValueError("Expected an unpublished matching model entry")
contents = {}
for relative in sorted(native["licenses"]):
    path = root / relative
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != native["files"][relative]:
        raise ValueError(f"Missing or altered license: {relative}")
    contents[relative] = path.read_bytes()
provenance = {"model": native["model"], "profile": native["profile"], "source": native["source"], "runtimePackageID": native["candidate"], "nativePackageManifestSHA256": hashlib.sha256(native_path.read_bytes()).hexdigest()}
contents["MODEL_PROVENANCE.json"] = (json.dumps(provenance, indent=2, sort_keys=True) + "\n").encode()
contents["MODEL_SHA256SUMS"] = f"{expected}  {model.name}\n".encode()
archive = root / "gigaam-600m-F16-notices.zip"
with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
    for name, data in sorted(contents.items()):
        info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
        info.create_system = 3
        info.external_attr = 0o100644 << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        output.writestr(info, data, compresslevel=9)
assets = [{"name": model.name, "byteSize": model.stat().st_size, "sha256": expected}, {"name": archive.name, "byteSize": archive.stat().st_size, "sha256": hashlib.sha256(archive.read_bytes()).hexdigest()}]
plan = {"schemaVersion": 1, "publicationState": "not-published", "repository": args.repository, "tag": args.tag, "targetCommit": subprocess.check_output(["git", "-C", str(Path(__file__).resolve().parents[2]), "rev-parse", "HEAD"], text=True).strip(), "nativePackageAcceptance": native["acceptance"], "nativePackageManifestSHA256": provenance["nativePackageManifestSHA256"], "modelEntrySHA256": hashlib.sha256((root / "model-manifest-entry.json").read_bytes()).hexdigest(), "assets": assets}
(root / "gigaam-publication-plan.json").write_text(json.dumps(plan, indent=2) + "\n")
(root / "gigaam-publication.sha256").write_text("".join(f"{asset['sha256']}  {asset['name']}\n" for asset in assets))
print(json.dumps(plan, indent=2))
