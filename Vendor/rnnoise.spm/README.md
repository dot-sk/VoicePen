# RNNoise SwiftPM wrapper

This local package contains the unmodified RNNoise 0.2 library sources required
by VoicePen. The upstream source is
<https://github.com/xiph/rnnoise/releases/tag/v0.2> and is licensed under the
BSD 3-Clause license in `COPYING`.

The default model is stored as a loadable binary in
`VoicePen/Resources/rnnoise-model-v0.2.bin`. It was generated with the upstream
`dump_weights_blob` utility from Xiph model revision `0b50c45`.

`rnnoise_model.c` contains the upstream layer-description function separated
from the generated 29 MB `rnnoise_data.c`; the generated weight arrays are not
compiled because VoicePen loads the binary model instead.
