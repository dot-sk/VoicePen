## Context

Language controls currently expose effective decoder capabilities instead of user intent. Models and the language preference are already stored in SQLite settings. Native pipelines capture requests before execution.

## Goals / Non-Goals

Make shared language actions route to compatible models. Keep native recognizers, downloads and captured requests unchanged.

## Decisions

Use a small pure selection policy for language compatibility and deterministic model fallback. Keep AppController as the command facade and reuse existing runtime warmup after selection. Store the small language-to-model dictionary as JSON in an additive settings key, committing it with language/model in one SQLite transaction. A new table or backend language forcing adds no value here.

Explicit model selection wins: selecting English-only Nemotron selects English. Explicit language selection first restores its last-used compatible model regardless of installation state or whether the current model supports the language too. Only missing catalog entries or incompatible remembered choices fall through to the current model and installed fallbacks. Auto requires multilingual support; system selection is checked against the resolved locale. Store remembered pairs only for actual selected language intents, not every advertised supported language.

## Risks / Trade-offs

Older versions did not record per-language model history, so an initial switch may use the installed fallback. Missing models are never downloaded silently. Backend effective language can differ from intent for GigaAM, which continues automatic CTC. Atomic persistence avoids publishing half of a selection update.
