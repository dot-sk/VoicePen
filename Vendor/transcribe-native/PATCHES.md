# Patch ownership and update policy

VoicePen owns the local recipe, not a hosted fork. There is no new Git fork
commit yet. Exact candidate identity is the upstream archive digest and the
ordered patch digests in `VOICEPEN_SOURCE.json` and the package manifest.
Never substitute a mutable checkout or an invented fork revision.

`0001-multilingual-research.patch` preserves the five-file prototype. It adds
parameterized multilingual experiments and corrected dump lifetimes. This is
byte-identical to the research handoff and is retained for review provenance.

`0002-supported-profile-and-isolation.patch` promotes the profile. It owns
version/configuration/vocabulary validation, strict explicit prompting for the
new model only, Metal graph placement checks, abort checkpoints, the shared
native stock25 planner, all-block diagnostics, tool target dependencies,
source identity, and isolated framework linkage/resource ownership. It does
not change VoicePen, existing v3 window planning, or the normal host head.

Embedded Metal sources belong to the framework binary. This compile mode
omits the upstream resource lookup Objective-C class, so it does not register
`GGMLMetalClass` and does not search another runtime's bundle or environment.
Nonembedded developer builds use `VoicePenGigaAMMetalClass`. The dynamic
framework contains private static ggml, exports only `transcribe_*`, and uses
an `@rpath` install name. A standalone smoke is insufficient to prove
coexistence with Whisper; the consumer integration owns the combined test.

Potential upstream contributions are the examples-disabled tool dependency
fix, complete multilingual profile, and scheduler placement diagnostics.
Packaging isolation is local policy. Review each patch on dependency updates;
do not bulk-sync ggml independently of transcribe.cpp's pinned patches.

Rebuild and rerun contract, numerical, full-corpus, C/Swift package, license,
and existing-family gates for any runtime/model/converter/reference/scorer or
toolchain change. Missing private fixtures are a failed acceptance gate, not
an optional CI success. The update gate must retain per-recording failures.

Rollback selects an immutable known-good package/model pair only after
checksum/interface/resource/license verification. A rejected candidate never
replaces that pair. This repository currently has no accepted GigaAM package;
Whisper remains the existing application dependency. No user data migration,
settings cleanup, publication, commit, or app change belongs to this recipe.
