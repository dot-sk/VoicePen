## Review of the confidence policy

The existing Q8 baseline was rerun once on the same 32 confirmed working recordings with its existing Russian glossary, full audio context, bestOf 5, temperature fallback 0.2, Metal, and the current audio processing. This validates confidence extraction, not a new ASR configuration or an independent accuracy evaluation. No FP16 inference or additional model was used. All 32 output texts matched the previous baseline exactly.

Production word reconstruction yielded 579 scored words. A minimum-token threshold of 0.5 marked 48 words in 25 sessions. Threshold 0.3 marked 14 words in 13 sessions and is the chosen initial review policy. These are descriptive counts on the development corpus, not calibrated accuracy or a tuning result on unseen data.

Examples inspected against confirmed references:

- Useful hints at 0.3: "волну" instead of "луну", score 0.138; "фигок" instead of "сжег", score 0.205; "Останавливать" versus the reference "Останови б.", score 0.250
- False positives: correctly recognized "Аргон", score 0.243, and "Luna", score 0.261, still needlessly attract review; "датасет", score 0.267, is equivalent to the reference's "дата сет"
- Missed error: "Сеньорики" instead of "синьорити", score 0.395, is not highlighted at the chosen threshold
- Another missed error: the extra final word "тесты" in sample-039, score 0.444, remains unhighlighted
- At 0.5, correct words such as "Делай", score 0.483, and "Ну", score 0.485, also became hints

The UI explains that hints suggest review and that unhighlighted words can still be wrong. It does not show numerical correctness percentages. Private inputs and per-token evidence remain under `.local/asr-quality/confidence-review-20261022/`.

## GigaAM native extension

The confidence-capable backend was paired with the previous backend rebuilt using the same Xcode toolchain, SDK, native build flags, existing F16 model, four threads, automatic language and greedy CTC. Both received identical 16 kHz mono Float32 versions of all 42 confirmed input files, with no added signal processing. Source audio hashes were verified. These inputs test the native decoder and are not a measurement of the complete app preprocessing/insertion flow.

Each recording had one excluded same-input warmup and three measured calls per run. Runs were previous backend, confidence backend, then previous backend again, with no competing build or inference work during timing. All 378 measured calls completed. For every matching recording/repeat, text, token IDs, token text and frame positions were identical across all three runs. All emitted candidate probabilities were finite and within [0, 1]. Model SHA-256 remains `06b1224edb7eb9b9b797c5d25539b6aa852e6a069fbfdce706760a3135e26cae`.

| Native runtime | p50 | p95 |
| --- | --- | --- |
| Previous, before | 69.76 ms | 363.32 ms |
| With confidence | 74.97 ms | 368.89 ms |
| Previous, after | 71.95 ms | 365.67 ms |

This run shows a few milliseconds of additional native latency, with variation between controls. It is not evidence of a speed improvement or a precise universal overhead. Replaying the 126 candidate outputs through production Swift word mapping took median 0.257 ms, maximum 2.015 ms; these mapping measurements exclude native inference, history persistence and insertion.

The 42 unique outputs contained 846 scored words. Whisper's 0.3 threshold would mark none. GigaAM threshold 0.8 marked 77 words; 0.7 marked 49; 0.6 marked 30; 0.5 marked 13. Choose 0.6 as a conservative initial review policy rather than highlighting many ordinary correct words. This is descriptive development-corpus review, not held-out calibration or correctness percentages.

Inspected examples:

- Useful hints: "оную" instead of "луну", score 0.457; "какуй" instead of "какой", 0.579; "токинов" instead of "токенов", 0.529
- False positives: "чейндж", 0.524, matches the reference; "новые", 0.552, is also correctly recognized
- Missed errors: "взяла" instead of "взял", 0.689, and "жок" instead of "сжег", 0.713, remain unhighlighted

Alternate English/Cyrillic spellings and number formatting are not classified as recognition errors here. No WER or hint precision is claimed from these examples. The threshold is preserved with each stored hint; old Whisper hints keep their default threshold. No new UI element or second recognizer is used.

Private paired evidence, package/source identities and the machine-readable verdict are under `.local/asr-quality/gigaam-confidence/`.
