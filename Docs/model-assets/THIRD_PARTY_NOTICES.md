# VoicePen Model Assets Third-Party Notices

The `model-assets-v1` GitHub Release mirrors model files used by VoicePen for
fully local transcription and speaker diarization. VoicePen does not claim
ownership of these model weights.

## Whisper large-v3 turbo

- Upstream implementation and models: https://github.com/ggerganov/whisper.cpp
- Original Whisper project: https://github.com/openai/whisper
- License: MIT
- Mirrored variants: GGML Q5_0, Q5_1, Q8_0 and the Core ML encoder.

Copyright holders retain their respective copyrights. Permission is granted,
free of charge, to any person obtaining a copy of this software and associated
documentation files to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies, subject to inclusion of this notice. The
software is provided without warranty of any kind.

## SpeakerKit Core ML diarization models

- Converted model repository: https://huggingface.co/argmaxinc/speakerkit-coreml
- SpeakerKit runtime: https://github.com/argmaxinc/argmax-oss-swift (MIT)
- Segmenter source: https://huggingface.co/pyannote/segmentation-3.0 (MIT)
- Embedder source and model-license policy: https://github.com/wenet-e2e/wespeaker/blob/master/docs/pretrained.md#model-license
- The selected WeSpeaker model follows the VoxCeleb dataset CC BY 4.0 license: https://creativecommons.org/licenses/by/4.0/
- PLDA clusterer source: https://github.com/BUTSpeechFIT/VBx (Apache-2.0)

The mirrored SpeakerKit archive keeps the README files shipped beside each
selected model variant. The converted `speakerkit-coreml` repository does not
currently declare one top-level license for the compiled Core ML artifacts;
the archive is redistributed with the upstream notices and this attribution.
