---
license: mit
language:
- ru
- en
- kk
- ky
- uz
pipeline_tag: automatic-speech-recognition
---

# GigaAM Multilingual

GigaAM Multilingual is a family of Conformer-based foundation models (220M / 600M parameters) pre-trained with a HuBERT-style objective on **2M hours** of speech across **70+ languages** and fine-tuned for speech recognition with character-wise CTC decoders on 50K hours.

The models provide best-in-class open-source quality on Russian, Kazakh, Kyrgyz, and Uzbek, and moderate quality on English.

GigaAM Multilingual includes the following model variants:
- `ssl` — 220M self-supervised encoder
- `ctc` — 220M ASR model with a character-wise CTC decoder
- `large_ssl` — 600M self-supervised encoder
- `large_ctc` — 600M ASR model with a character-wise CTC decoder

## Model Performance

Word Error Rate (%) on [Common Voice](https://commonvoice.mozilla.org) (CV), [FLEURS](https://huggingface.co/datasets/google/fleurs), and internal in-the-wild test sets. Utterances longer than 30 s and references containing digits are excluded; references/hypotheses are normalized (lowercasing, punctuation removal, numerals→words); greedy decoding. Best per row in **bold**.

| Language | Dataset | GigaAM Multilingual | GigaAM Multilingual Large | Omnilingual 1B (LLM) | Seamless M4T large v2 | Whisper large v3 |
|:--------|:--------|------------:|------------:|---------------------:|----------------------:|-----------------:|
| English | CV       |        26.0 |        21.5 |                 24.7 |              **16.2** |             20.0 |
| English | FLEURS   |        12.2 |         9.4 |                  7.1 |                   5.8 |          **3.9** |
| Russian | CV       |         7.1 |     **5.1** |                 13.6 |                    9.2 |              9.1 |
| Russian | FLEURS   |         4.4 |     **3.0** |                  6.4 |                    4.6 |              3.1 |
| Russian | Internal |         7.6 |     **6.0** |                 14.6 |                   16.1 |             10.1 |
| Kazakh  | CV       |        17.2 |    **13.8** |                 23.7 |                   23.8 |             57.8 |
| Kazakh  | FLEURS   |         5.2 |     **4.4** |                  6.6 |                    6.8 |             32.4 |
| Kazakh  | Internal |        18.8 |    **15.8** |                 32.2 |                   62.9 |             65.2 |
| Kyrgyz  | CV       |        12.5 |    **10.2** |                 21.6 |                   14.3 |             95.2 |
| Kyrgyz  | FLEURS   |         7.0 |     **5.5** |                  8.1 |                    9.5 |             86.3 |
| Kyrgyz  | Internal |        11.1 |     **9.8** |                 25.0 |                   78.3 |            102.2 |
| Uzbek   | CV       |        11.3 |     **9.2** |                 32.8 |                   25.1 |            109.9 |
| Uzbek   | FLEURS   |        10.0 |     **7.3** |                 15.4 |                   11.9 |            105.4 |
| Uzbek   | Internal |        13.8 |    **12.7** |                 30.2 |                   40.0 |            120.6 |


## Usage

```python
from transformers import AutoModel

revision = "ctc"  # any variant: ssl, ctc, large_ssl, large_ctc
model = AutoModel.from_pretrained(
    "ai-sage/GigaAM-Multilingual",
    revision=revision,
    trust_remote_code=True,
)

transcription = model.transcribe("example.wav")
print(transcription)
```

Recommended versions:
- `torch==2.10.*`, `torchaudio==2.10.*`
- `transformers==5.*`
- (any) `hydra-core`, `omegaconf`

Full usage guide can be found in the [example](https://github.com/salute-developers/GigaAM/blob/main/colab_example.ipynb).

## Fine-tuning to a new language

The `ssl` / `large_ssl` backbones can be adapted to a new language — see the [fine-tuning guide](https://github.com/salute-developers/GigaAM/blob/main/train_utils/README.md) and the [example notebook](https://github.com/salute-developers/GigaAM/blob/main/train_utils/example.ipynb).

## Citation

```bibtex
@misc{gigaam_multilingual,
      title={GigaAM Multilingual: Foundation Model for Underrepresented Languages},
      author={Andrei Kuzmenko and Alexandr Maximenko and Aleksandr Kutsakov and Georgii Gospodinov and Dmitrii Bolotov and Oleg Kutuzov and Pavel Bogomolov and Fyodor Minkin},
      year={2026},
      eprint={2607.10371},
      archivePrefix={arXiv},
      primaryClass={eess.AS},
      url={https://arxiv.org/abs/2607.10371}
}
```
