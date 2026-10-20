# Public speech fixtures

`public-speech.json` pins audio content and provenance only. Audio and tensor
outputs remain ignored. These five samples exercise automatic multilingual
CTC token decoding, not broad language accuracy. They do not modify the private
27-recording gold set, normalization, spelling aliases or acceptance thresholds.

Russian, English, Kyrgyz and Uzbek are the first validation row of Google
FLEURS at dataset revision `70bb2e84b976b7e960aa89f1c648e09c59f894dd`, licensed
CC-BY-4.0. Credit Google FLEURS contributors. Samples are saved as 16 kHz mono
Float32 WAVs for identical native/reference inputs.

The FLEURS Kazakh viewer could not read any split because each row group
exceeded its 300 MB scan limit. The Kazakh fixture is instead Esetok's human
pronunciation of "nöl", published under CC0 on Wikimedia Commons as
`File:Kk-0-nöl.ogg`, with source SHA-1
`56df543508f40df93704151664d28e79dac77101`. Its source audio is resampled to
16 kHz mono Float32 WAV by FFmpeg. This conversion affects only the new public
fixture. Both runtimes receive that exact converted byte sequence.

Sources and license terms:

- https://huggingface.co/datasets/google/fleurs/tree/70bb2e84b976b7e960aa89f1c648e09c59f894dd
- https://creativecommons.org/licenses/by/4.0/
- https://commons.wikimedia.org/wiki/File:Kk-0-n%C3%B6l.ogg
- https://creativecommons.org/publicdomain/zero/1.0/
