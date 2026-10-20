# VoicePen GigaAM package

Both app and SwiftPM consume this local binary wrapper. Its framework contains
private ggml and embedded Metal kernels. It does not depend on Python or MLX.

The current `candidate-manifest.json` is an **unaccepted local candidate**.
Prepare it for integration evaluation with:

```sh
bash scripts/prepare-gigaam-runtime.sh .local/asr-quality/native-gigaam-600m/package --allow-unaccepted-candidate
```

The preparation command compares the exact manifest and verifies every packaged
file digest. Artifacts and weights stay outside Git. Reproduce the native
package using `Vendor/transcribe-native/README.md`. Release adoption requires the
predecessor acceptance gates, an accepted manifest, model-assets publication,
and application integration evidence. A candidate build is not a distributable
release. Keep `candidate-manifest.json` updated only after reviewing the new
package and rerunning affected gates.
