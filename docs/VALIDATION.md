# Validation — 2026-10-07

## Verified

- Shared Swift package: 47 tests in 13 suites passed. Coverage includes local filtering, provider response validation, cancellation, request coalescing, cache invalidation, quota accounting, personal vocabulary, adjustable candidate counts and register ordering.
- Python vocabulary maintenance: two tests passed.
- Offline evaluation: 170 cases processed without errors; 29 designated non-Japanese, translation or instruction cases rejected locally. This is not a live-model quality result.
- Native macOS arm64 Release application and converter service built, signed and installed. Fixed Japanese sentences exercised conversion, suggestions, keyboard acceptance and the safe copy fallback for palette clicks.
- Native iPhone Release application and keyboard extension built, signed, installed and launched. Device use confirmed conversion and provider suggestions. The candidate panel and compact application titles were revised following device feedback.
- Public upstream patches apply to the pinned source revisions. Public-source scan found no configured local identities, detected credentials or personal home paths.

## Still to validate

- Broad device and host-app compatibility, landscape, iPad, larger text sizes and prolonged keyboard use.
- A controlled latency benchmark and a native-speaker review of model output. Successful samples do not establish a reliability or quality rate.
- Credential sharing on a fresh installation under a different developer account.
- A complete audit of embedded dictionaries, models and transitive binary components before publishing installable applications.

See ../MANUAL_TESTS.md for further acceptance checks. Build success does not establish visual or behavioral correctness in every host application.
