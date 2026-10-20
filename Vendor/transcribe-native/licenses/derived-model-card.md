---
license: mit
language:
- ru
- en
- kk
- ky
- uz
library_name: gigaam-multilingual-mlx
pipeline_tag: automatic-speech-recognition
inference: false
base_model: ai-sage/GigaAM-Multilingual
tags:
- mlx
- apple-silicon
- gigaam
- ctc
- automatic-speech-recognition
---

# GigaAM-Multilingual MLX FP16

An independent Apple MLX port of the official [GigaAM repository](https://github.com/salute-developers/GigaAM) and the [GigaAM-Multilingual source model](https://huggingface.co/ai-sage/GigaAM-Multilingual). It is not an official GigaChat/GigaAM release.

This repository contains the **float16** reference MLX artifact. Select this variant explicitly with `--variant`.

- Code and CLI: [https://github.com/ai-babai/gigaam-multilingual-mlx](https://github.com/ai-babai/gigaam-multilingual-mlx)
- PyPI package: [`gigaam-multilingual-mlx`](https://pypi.org/project/gigaam-multilingual-mlx/)
- All variants: [GigaAM Multilingual MLX Collection](https://huggingface.co/collections/ai-babai/gigaam-multilingual-mlx-6a57ef36e44d1a0c4eb49276)
- Full reproducible benchmark: [v0.1.0 report](https://github.com/ai-babai/gigaam-multilingual-mlx/blob/v0.1.0/docs/benchmark-v0.1.0.md)

## Install and transcribe

Requires macOS 14 or newer on Apple Silicon and Python 3.12 or 3.13.

```bash
python -m pip install gigaam-multilingual-mlx==0.1.0
gigaam-multilingual-mlx transcribe audio.wav --variant fp16 --format json --output transcript.json
```

The package downloads the pinned `v0.1.0` snapshot into the standard Hugging Face cache. Input may be WAV, FLAC, MP3, M4A, or a video readable by `ffmpeg`; output may be TXT, JSON, SRT, or VTT.

```python
from gigaam_multilingual_mlx import load_model
from gigaam_multilingual_mlx.cli import transcribe_file

model = load_model(variant="fp16")
result = transcribe_file(model, "audio.wav")
print(result["text"])
```

## Artifact

- Hub revision: `v0.1.0`
- Source revision: `3905cd51c3ed4e88c8edf33f3302969ba480a327`
- Weights: `model.safetensors` — 1,170,775,344 bytes
- Weights SHA-256: `d6d7bcef5e1b77700c84d669635a88021724fd3b1ae0c408890bccdf3c8d2269`
- Config SHA-256: `72c544eec78996dc57ed88f8308d735647644e981ec81f46ce945ee1b027a174`
- Runtime compatibility: `gigaam-multilingual-mlx>=0.1.0,<0.2.0`, `mlx>=0.32,<0.33`

`manifest.json` records source and parent revisions, hashes, conversion metadata, quantization rules, strict-load validation, and compatibility without machine-local paths.

## Quality, speed, and memory

Measured on one MacBook Pro with Apple M4 Pro and 48 GB unified memory. Quality uses the public FLEURS `ru_ru`, Russian LibriSpeech, and SOVA subsets. Performance below is the five-run warm median on the deterministic 5-minute public corpus, with greedy CTC, 20-second chunks and 2-second overlap. Peak RSS is resident process memory; device memory is shown separately and the two must not be added.

| Implementation | Disk | FLEURS WER | Ru Libri WER | SOVA WER | 5 min warm | Speed vs Original | Peak RSS | Device peak |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Original PyTorch/MPS | 2.342 GB | 6.271% | 5.911% | 12.448% | 3.023s | 1.00× | 5.019 GB | 4.064 GB |
| MLX FP16 | 1.171 GB | 6.271% | 5.929% | 12.431% | 2.089s | 1.45× | 1.348 GB | 1.918 GB |
| MLX INT8 g64 (default) | 0.699 GB | 6.292% | 5.911% | 12.481% | 2.332s | 1.30× | 0.879 GB | 1.215 GB |
| MLX INT6 g64 | 0.573 GB | 6.249% | 6.022% | 12.465% | 3.142s | 0.96× | 0.755 GB | 1.090 GB |
| MLX INT4 g64 | 0.447 GB | 6.358% | 6.003% | 12.581% | 2.750s | 1.10× | 0.628 GB | 0.964 GB |

INT8 is the default for its quality/size/memory balance, not because it is always the fastest. See the full report for cold/load timings, p95, 30-second and 20-minute profiles, CER, deltas, hashes, commands, and limitations.

## Intended use and limitations

Intended for local, offline automatic speech recognition in Russian, English, Kazakh, Kyrgyz, and Uzbek on Apple Silicon. It is not a diarization system, streaming microphone server, forced aligner, or cloud service. Word timestamps are approximate greedy-CTC frame timings. Accuracy can degrade with noise, far-field speech, accents, code-switching, music, overlapping speakers, or domains unlike the public evaluation subsets.

Only Apple M4 Pro was benchmarked for this release. M1-M5 machines are expected to be runtime-compatible within the documented macOS/MLX range, but they are not claimed to have the same speed or memory figures.

## License and provenance

The MLX port and converted artifacts are released under MIT, matching the upstream license. See [`LICENSE`](LICENSE) and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). The exact upstream repository is [https://github.com/salute-developers/GigaAM](https://github.com/salute-developers/GigaAM); the source model card is [https://huggingface.co/ai-sage/GigaAM-Multilingual](https://huggingface.co/ai-sage/GigaAM-Multilingual).

## Citation

Please cite both this MLX software release and the original GigaAM-Multilingual work:

```bibtex
@software{popkov2026gigaammlx,
  author = {Maksim Popkov},
  title = {GigaAM-Multilingual MLX},
  year = {2026},
  version = {0.1.0},
  url = {https://github.com/ai-babai/gigaam-multilingual-mlx}
}

@misc{gigaam_multilingual,
  title = {GigaAM Multilingual: Foundation Model for Underrepresented Languages},
  author = {Andrei Kuzmenko and Alexandr Maximenko and Aleksandr Kutsakov and Georgii Gospodinov and Dmitrii Bolotov and Oleg Kutuzov and Pavel Bogomolov and Fyodor Minkin},
  year = {2026},
  eprint = {2607.10371},
  archivePrefix = {arXiv},
  primaryClass = {eess.AS},
  url = {https://arxiv.org/abs/2607.10371}
}
```
