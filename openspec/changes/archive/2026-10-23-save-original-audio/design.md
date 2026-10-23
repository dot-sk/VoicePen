## Approach

Schedule dictation saving immediately after the minimum-duration check, before model preparation or preprocessing. Keep transcription on its current derived file path.

Use the existing timeline mixer in a separate raw-mix mode to combine captured meeting sources without microphone denoising, source leveling, or peak scaling. Sum simultaneous samples so a silent captured source cannot attenuate an active one; clamp only sums outside the output PCM range. The raw mix runs concurrently with the existing transcription mastering path. Schedule one copy of that temporary mix and wait for mixing and copying before removing captured source files. Retry processing has no archive call.

Retention keeps its existing per-file behavior. Existing top-level audio files remain valid retention items. A failed mix or copy logs the failure without changing transcription.
