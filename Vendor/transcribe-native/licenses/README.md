# License provenance

The candidate keeps separate notices for transcribe.cpp, its vendored ggml,
source GigaAM code/model, and the derived MLX conversion input.

- `LICENSE.transcribe` is the MIT notice from upstream commit
  `1dc22facfc931e2f8adb43924b0e38b9c46f83c7`.
- `LICENSE.ggml` is the MIT notice from the vendored ggml tree at
  `d7cb574130e6f01ad25b3289685489200febcd74`, including the two upstream
  transcribe.cpp downstream patches listed in `pins.json`.
- `source-model-card.md` is the original model card at Hugging Face source
  revision `3905cd51c3ed4e88c8edf33f3302969ba480a327`. Its declared model
  license is MIT. That revision has no separate LICENSE file. The five
  ASR languages are ru, en, kk, ky, uz. The encoder's 70+ pretraining
  languages are not an ASR capability claim.
- `LICENSE.source-repository` is the full GigaChat Team MIT notice fetched
  from `salute-developers/GigaAM` commit
  `7447938d791c4f3e643386ee22c33777004293a5`. It agrees with the full original
  notice included by the derived artifact's `THIRD_PARTY_NOTICES.derived.md`.
- `LICENSE.derived-model`, `derived-model-card.md`, and
  `THIRD_PARTY_NOTICES.derived.md` retain the separate ai-babai converter
  notice and its explicit upstream checkpoint provenance. The card and
  notices are pinned at `ai-babai/gigaam-multilingual-mlx` tag `v0.1.0`;
  their exact bytes are included in each package's SHA-256 content manifest.
  The local source weight/config digests are independently pinned.

MIT permits redistribution with the copyright and permission notices. No
noncommercial or separate model-specific restriction appears in these saved
source documents. This audit records the documents and conditions; it does
not publish or accept a package. A changed or missing notice blocks the
update gate. The package also copies the upstream miniz and silero_vad
third-party notices. Private corpus content and weights are never checked in.

Sources:

- https://huggingface.co/ai-sage/GigaAM-Multilingual/blob/3905cd51c3ed4e88c8edf33f3302969ba480a327/README.md
- https://github.com/salute-developers/GigaAM/blob/7447938d791c4f3e643386ee22c33777004293a5/LICENSE
- https://huggingface.co/ai-babai/gigaam-multilingual-mlx/blob/v0.1.0/THIRD_PARTY_NOTICES.md
