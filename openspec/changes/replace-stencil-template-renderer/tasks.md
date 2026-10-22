## 1. Capture compatibility

- [ ] 1.1 Inventory shipped/repository templates and read available local user templates without modifying or publishing their contents. Record supported and unsupported constructs; preserve full-Stencil scope reduction explicitly in migration documentation.
- [ ] 1.2 Capture a differential fixture oracle from the pinned current engine for all shipped templates and supported variables/filter chains, preserving literal whitespace, Unicode, empty args, multiple substitutions and variable values containing template delimiters. Keep Stencil only in a temporary evaluation harness until comparison passes.

## 2. Implement bounded rendering and diagnostics

- [ ] 2.1 Implement the complete linear grammar with typed errors, existing transforms and one-pass value substitution; add behavior tests for supported rendering and nonrecursive inserted-data scenarios. Test all eight filters, their order and exact output parity with captured fixtures.
- [ ] 2.2 Add parser tests for unknown variable/filter, filter arguments, missing/stray/nested delimiters and unsupported control/comment tags. Validate fully before returning output, including a template with valid substitutions followed by invalid syntax.
- [ ] 2.3 Add per-command config validation through the existing diagnostic path; automate the unsupported-config scenario so one bad command preserves valid commands/aliases and does not rewrite the config file.
- [ ] 2.4 Automate invalid-trigger fallback with a configured pasteAndSubmit action and an overlapping general trigger: retain normalized dictation plus diagnostic, select no alternative command, insert no partial command and never submit. Preserve existing valid-template insertion behavior.
- [ ] 2.5 Automate the corrected-template reload scenario through the config store and command processor, without restart or settings changes. Retain existing matching/alias/filter regressions.

## 3. Remove dependencies and verify

- [ ] 3.1 Remove Stencil and PathKit from SwiftPM/Xcode only after parity passes and no other consumer remains; refresh resolved graphs. Confirm test-only Spectre and CLI/test packages are not misreported as linked runtime savings. Remove the temporary oracle harness dependency from production wiring.
- [ ] 3.2 Compare Release size/link inputs and render timing before/after without claiming unmeasured improvements. Document the grammar, unsupported syntax and diagnostic-based migration without changing user files.
- [ ] 3.3 Run make test, make build, focused formatting and strict OpenSpec validation; record exact checks and limitations. Sync verified delta specs before any later archive and do not commit/release without a separate request.
