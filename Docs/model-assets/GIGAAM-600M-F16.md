# GigaAM F16 model publication review

Published with user authorization on 2026-10-19. Both public assets passed
complete byte-size and SHA-256 readback before the bundled entry was activated.

Release: https://github.com/dot-sk/VoicePen/releases/tag/model-assets-gigaam-600m-f16-v1

- Repository: `dot-sk/VoicePen`.
- New immutable tag: `model-assets-gigaam-600m-f16-v1`.
- Target commit: `4a8343646d25bf65174ce7d8b162681f9c1388cd`.
- Existing `model-assets-v1` assets and the application's latest release are
  preserved. The new release is explicitly non-latest.
- Before publication, read-only checks confirmed the target commit existed
  and the new tag/release was absent. The created release ID is `417433070`.

Exactly two uploaded assets:

| Asset | Bytes | SHA-256 |
|---|---:|---|
| `gigaam-600m-F16.gguf` | 1,172,222,176 | `06b1224edb7eb9b9b797c5d25539b6aa852e6a069fbfdce706760a3135e26cae` |
| `gigaam-600m-F16-notices.zip` | 13,262 | `96fad5236215500ca3e14c9059a49ada7f62dcdc77b5f8329c4ce05e36e98710` |

The deterministic ZIP contains the ten original license/provenance files from
the pinned native package, `MODEL_PROVENANCE.json` and `MODEL_SHA256SUMS`.
It includes source and derived-model MIT notices, both saved model cards,
transcribe.cpp/ggml/miniz/Silero notices, source/checkpoint revisions and hashes.
It contains no native executable, private audio or evaluation transcripts.
Canonical native manifest SHA:
`7738da1d56246941906071a4177dd5586dd02c5560df4d97eb6fee72b52626e8`.
That manifest retains its original unaccepted status; model-asset review does
not claim native framework/app distribution acceptance or macOS 15 runtime
verification.
The separate `host-local-acceptance.json` accepts the exact model artifact's
content, deterministic conversion, F16 stock25 quality and saved licenses.
Its SHA is
`f83c682dc7a37f2e1b8be461ab2925f72a0e8d479846e55871e4ba7917983b40`.
The publisher requires that matching model acceptance before creating a release;
`GIGAAM_MODEL_ACCEPTANCE_REPORT` may select its location. The native package's
separate distribution status does not authorize or block publication of these
model-only assets. User authorization is still required before `--publish`.

## Commands

Local inputs already exist at
`.local/asr-quality/gigaam-app-publication-inputs-v3/`.
The original plan is `gigaam-publication-plan.json`; its preparation entry has
no download URL. `verified-model-manifest-entry.json` and
`publication-receipt.json` record the completed public readback.

```sh
bash scripts/publish-model-assets.sh --gigaam \
  .local/asr-quality/gigaam-app-publication-inputs-v3 --dry-run
```

The authorized first-publication command was:

```sh
bash scripts/publish-model-assets.sh --gigaam \
  .local/asr-quality/gigaam-app-publication-inputs-v3 --publish
```

The command refuses any existing release or tag, creates a fresh draft, uploads
only the two named files without clobber, checks remote sizes and publishes as
non-latest. Draft lookup and publication use the numeric release ID because
GitHub's tag lookup can return 404 for a draft. It then downloads both assets from their public HTTPS release URLs
and checks their full size and SHA-256. Only after both checks does it write
`verified-model-manifest-entry.json` and `publication-receipt.json` locally.
It never edits the bundled manifest. A failed upload leaves a draft for review;
the publisher will not replace that draft automatically.

If publication succeeded but public readback failed, retry without remote
mutation:

```sh
bash scripts/publish-model-assets.sh --gigaam \
  .local/asr-quality/gigaam-app-publication-inputs-v3 --verify-only
```

Only the resulting verified entry may be used to activate the bundled GigaAM
download. The expected future model coordinate is
`https://github.com/dot-sk/VoicePen/releases/download/model-assets-gigaam-600m-f16-v1/gigaam-600m-F16.gguf`;
it is published and passed public readback. Do not rerun `--publish` for this
immutable tag; use `--verify-only` to repeat readback.

## Local verification

- Full local byte-size/SHA verification and offline publisher dry-run passed.
- ZIP license membership/hashes and repeat-build determinism passed.
- Isolated gh/curl doubles verified legacy-tag refusal, existing-release
  protection without mutation, unaccepted-model refusal, failed-readback suppression, successful
  readback/schema generation and stale receipt cleanup. These simulations
  performed no network writes and do not substitute for actual public readback.
- Re-run those checks with
  `uv --native-tls run --no-project --python 3.13 python Tools/GigaAMIntegration/check_publication.py ASSETS_DIR`.
- Shell syntax, strict OpenSpec validation and `git diff --check` passed.
- Actual publication initially stopped at a draft-by-tag 404 after both files
  had uploaded. The same draft was verified by ID and published without a
  duplicate release. A regression fixture now covers that behavior and refusal
  to modify an existing draft. Public readback exited successfully; logs are
  `/private/tmp/gigaam-publication-20261019.log` and
  `/private/tmp/gigaam-public-readback-20261019.log`.
