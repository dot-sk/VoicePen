## Purpose

Provide the measured GigaAM Multilingual 600M checkpoint as a reproducible native library capability with verified recognition parity, explicit execution behavior, and a callable package for future application integration.

## ADDED Requirements

### Requirement: Converted artifacts preserve checkpoint identity

Offline conversion SHALL preserve the pinned checkpoint's complete tensor set, tensor meaning, preprocessing configuration, vocabulary order, and CTC blank identity. Each converted artifact SHALL identify its source checkpoint, converter, runtime compatibility, precision, and content digests. Conversion and loading SHALL reject unsupported or inconsistent inputs instead of substituting a different model or guessing missing metadata.

#### Scenario: Convert the pinned floating checkpoint

- **WHEN** the converter receives the pinned floating checkpoint and matching configuration
- **THEN** it produces a loadable artifact with complete tensor accounting and verifiable provenance to that exact checkpoint

#### Scenario: Reject an inconsistent artifact

- **WHEN** conversion or loading encounters a missing tensor, incompatible shape, unsupported profile, damaged content, or inconsistent vocabulary metadata
- **THEN** it returns a specific failure without producing or exposing a ready model

### Requirement: Native inference preserves floating reference behavior

The native profile SHALL preserve the floating reference's audio preprocessing, sequence lengths, model computation, and CTC decoding under an explicitly matched context policy. Parity comparisons SHALL use identical logical weight values and matching documented activation arithmetic, and SHALL distinguish weight-storage precision from compute precision. Floating numerical parity SHALL pass declared per-stage tolerances and decoded-output checks before quantized artifacts are eligible for acceptance. Whole-input diagnostics SHALL remain separate from acceptance of the supported windowed path.

#### Scenario: Compare short speech with the floating reference

- **WHEN** native inference and the floating reference process the same short speech under the same recorded configuration
- **THEN** stage comparisons pass the declared numerical tolerances and the decoded transcript matches the reference

#### Scenario: Compare long speech with the floating reference

- **WHEN** native inference and the floating reference process the same long speech with matching window boundaries, context retention, and activation arithmetic
- **THEN** they cover the complete input and match reference decoding without truncation or boundary duplication

### Requirement: The primary profile preserves the measured windowed behavior

The supported primary profile SHALL use F16 weight storage, the Metal encoder, host CTC projection/search, and the measured policy of encoder windows no longer than 25 seconds with up to 2 seconds of context on either side. Context-only encoder frames SHALL be discarded, retained spans SHALL cover the full input exactly once, and CTC collapse SHALL operate on the stitched retained sequence. The runtime SHALL preserve real lexical repetitions and SHALL NOT merge separately decoded window texts. The selected context policy SHALL be versioned and reported, without requiring research environment flags.

#### Scenario: Run the primary profile without research overrides

- **WHEN** a caller loads the accepted primary profile and transcribes supported audio using normal defaults
- **THEN** it uses the declared F16 windowed policy and reports that policy and actual stage placement

#### Scenario: Speech and repetitions cross a window boundary

- **WHEN** a recording contains speech, blank transitions, or real repeated words across a retained-span boundary
- **THEN** each retained encoder frame is decoded once and reference-matched decoding preserves the utterance without added boundary text or loss of real repetitions

### Requirement: Precision variants pass independent corpus acceptance

F16-storage and native Q8 candidates SHALL each pass the frozen full-corpus protocol against the same accepted references before being labeled accepted. F16-storage inference SHALL preserve floating-reference transcripts with the same weight values, matching activation arithmetic, and the same window policy. It SHALL also preserve the frozen research F16-window baseline's base-normalized outputs and aggregate quality under every declared scoring protocol. A reference using different activation arithmetic or context policy SHALL remain a separate comparator, not a substitute parity oracle. Optional Q8 SHALL produce no regression in normalized word or character edit counts for any corpus recording relative to accepted F16, and SHALL produce no regression in aggregate WER or CER under the base and declared diagnostic protocols. Failure of optional Q8 SHALL NOT block availability of independently accepted F16. Research measurements SHALL remain reusable evidence but SHALL NOT alone establish acceptance of a different fork build or package.

#### Scenario: Evaluate a native precision candidate

- **WHEN** the full-corpus evaluation runs for an F16 or Q8 candidate
- **THEN** the report includes every recording exactly once, output alignments, variant-specific acceptance checks, model and runtime pins, protocol identity, timing, and memory evidence

#### Scenario: A precision candidate fails acceptance

- **WHEN** a candidate misses parity, quality, completeness, or provenance checks
- **THEN** it remains unaccepted and the report identifies the failing recordings and checks without replacing the accepted baseline

### Requirement: Metal requests have explicit execution results

The native runtime SHALL execute the encoder graph through Metal when the caller requires Metal. It SHALL report the requested and actual encoder backend, actual frontend and CTC projection/search placement, and relevant runtime/model identities. Unavailable Metal, missing resources, or unsupported encoder operations SHALL fail explicitly rather than silently executing the encoder on CPU. Supported CTC projection placement SHALL be selected from parity-verified alternatives using the recorded performance experiment. Diagnostics SHALL distinguish stage placement and timings and SHALL NOT claim full GPU inference while any model computation remains on the host.

#### Scenario: Required Metal is available

- **WHEN** a caller loads and runs the model with Metal required on a supported system
- **THEN** the encoder uses Metal and diagnostics identify actual stage placement and artifact identities

#### Scenario: Required Metal cannot execute

- **WHEN** required Metal or its packaged resources are unavailable or model inference cannot execute there
- **THEN** the operation reports a backend failure without a successful CPU-encoder fallback result

#### Scenario: Compare CTC projection placement

- **WHEN** host and Metal CTC projection candidates run the same full-corpus inputs, weights, and decoding options
- **THEN** the report compares projection/output parity, WER/CER, head time, and end-to-end latency, and a Metal-head candidate is selected only when it preserves acceptance behavior and demonstrates an end-to-end benefit beyond observed run-to-run noise

### Requirement: Capabilities describe the callable model honestly

The native model SHALL expose the checkpoint's supported languages and only the tasks, decoding controls, prompting, streaming, and timestamp granularity implemented and tested for this profile. Unsupported explicit options SHALL produce an unsupported-option result rather than being silently ignored or misrepresented as supported. Existing interface defaults SHALL resolve consistently with the advertised capabilities.

#### Scenario: Inspect profile capabilities

- **WHEN** a caller queries the multilingual CTC profile's capabilities
- **THEN** the returned language and feature metadata agrees with the model and its tested request behavior

#### Scenario: Request an unsupported option

- **WHEN** a caller explicitly requests an unimplemented task, language control, prompting control, decoding mode, streaming mode, or timestamp granularity
- **THEN** the runtime reports that the option is unsupported without returning a successful result that implies it was honored

### Requirement: Empty input and cancellation have defined outcomes

The native interface SHALL handle valid silence without invented speech and reject empty, too-short, non-finite, or malformed audio through its documented status contract. Cancellation SHALL terminate execution at bounded cooperative checkpoints, identify an aborted result, and preserve the interface's distinction between partial and complete output. A canceled or failed request SHALL NOT prevent a later valid request from using a valid loaded model.

#### Scenario: Process silence and invalid audio

- **WHEN** the caller supplies digital silence or invalid audio fixtures
- **THEN** silence returns no speech and invalid inputs return the documented validation failure without a crash or fabricated transcript

#### Scenario: Cancel and reuse a model

- **WHEN** a caller aborts a running request and then submits valid audio to the same model
- **THEN** the first request reports abortion with any partial output marked incomplete, and the later request completes normally

### Requirement: Native artifacts are reproducible and Swift callable

The dependency package SHALL contain a versioned native library, the existing C interface and import metadata usable by Swift, required Metal resources, checksums, and dependency/model license provenance. A clean supported Apple Silicon macOS environment SHALL build and run a Swift client without Python or MLX inference dependencies or development-checkout resource paths. Rebuilding pinned inputs SHALL reproduce model-content digests and the documented native artifact contents, with any toolchain-generated binary variation recorded.

#### Scenario: Build and consume a clean package

- **WHEN** the pinned build and conversion procedures run in a clean supported environment and a Swift client consumes the resulting package
- **THEN** it can query capabilities, load the model, run Metal transcription, cancel, and release resources using only packaged runtime dependencies

#### Scenario: Validate or roll back a dependency artifact

- **WHEN** package verification finds a changed digest, missing resource, incompatible interface, or incomplete license record, or a candidate update fails its regression gates
- **THEN** the candidate remains unaccepted and the previous pinned package remains reproducible and usable

### Requirement: Existing model families retain their contracts

Adding the multilingual profile SHALL preserve existing supported model families' loading, capabilities, inference output, and error contracts. Fork updates SHALL rerun the new profile's parity and package checks and the affected upstream regression suite before advancing the pin.

#### Scenario: Exercise existing profiles after the extension

- **WHEN** existing GigaAM v3 profiles and other affected model families run their regression fixtures against the fork
- **THEN** their results and supported options retain the pre-extension contracts

#### Scenario: Evaluate an upstream update

- **WHEN** the fork is rebased or its runtime, converter, compiler, or model inputs change
- **THEN** automated validation reruns the applicable compatibility, parity, full-corpus, package, and existing-family gates before accepting the new pin
