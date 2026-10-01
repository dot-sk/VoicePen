## Context

The promoted candidate contains the app archive, not the package checkout or Sparkle command-line tools. Appcast generation discovers sign_update in the release runner's DerivedData package artifacts.

## Decisions

Resolve existing project packages when promoting a candidate, before appcast generation. This obtains the pinned Sparkle tool without recompiling the app or changing the validated candidate.

## Risks / Trade-offs

Package resolution adds a network dependency to publication. A resolution failure stops publication instead of emitting unsigned update metadata.
