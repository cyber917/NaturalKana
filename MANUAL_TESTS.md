# Manual acceptance checklist

Use this checklist for each release. Unchecked items require evidence for the target device and host application; completed checks from development are summarized in docs/VALIDATION.md.

## Build, identity and signing

- [ ] Install full Xcode, select it for the build process, resolve all pinned dependencies and LFS model weights. Build both pristine upstream commits separately before declaring M0 passed.
- [ ] Build modified iOS host + keyboard and macOS IME + converter service in Release. Inspect warnings; test the complete packaged services, not only the shared package.
- [ ] Configure a personal development team and confirm App Groups / Keychain Sharing support. Install on the developer's device. Verify both host/extension can read only the intended shared provider key.
- [ ] Confirm NaturalKana name, separate bundle IDs, input-source IDs and no upstream logo/App Store identity on all screens. Historical upstream assets/screens still need audit.
- [ ] Resolve missing model/data license notices in THIRD_PARTY_NOTICES before redistribution.

## Privacy and field boundaries

- [ ] Before consent, while disabled, without Full Access, and without keys: no provider request or popup.
- [ ] Type Japanese then rapidly switch apps/fields (including another field in the same app); old suggestions disappear and cannot replace either field.
- [ ] Password/secure input, email, URL, phone and number fields: zero network calls. Toggle macOS Secure Input while a request is pending and before acceptance.
- [ ] Block an app by its bundle ID; verify no context query/request/acceptance in it.
- [ ] A multi-message conversation and text across newlines: inspect only a controlled test server/mock, confirm payload contains only the capped current draft and configuration/reference data.
- [ ] Inspect Release device logs: no drafts, API keys, responses or analytics. Audit remaining upstream debug/legacy features before shipping.
- [ ] OpenAI/Qwen endpoint errors, 401/429, offline, timeout, refusal and malformed JSON: hidden strip/panel, only settings status changes.

## iOS

- [ ] New install defaults to Japanese QWERTY romaji; flick, custom layouts and kana/kanji conversion still work.
- [ ] Type `今何にしていますか` in Messages and LINE, pause, inspect Japanese-only candidates within the selected limit above normal conversion candidates.
- [ ] The draft never changes until a chip is tapped. Late responses after additional typing cannot overwrite it.
- [ ] Marked text and live conversion ON/OFF; small/large characters, deletion, autocorrection, dictation and external keyboard behavior.
- [ ] Emoji with skin tones, family ZWJ, flags, combining marks and half-width kana: replacement deletes the exact graphemes and preserves earlier lines.
- [ ] Long lines (>200 graphemes): only the last 200 are replaced. No earlier content disappears.
- [ ] Cursor in the middle, selected text, unavailable/truncated proxy context: currently suppress suggestions. Full before/after-cursor support is an unimplemented acceptance item.
- [ ] Candidate-strip height at portrait/landscape, iPad floating keyboard, resizing, dark mode and large text. No clipped keyboard rows.
- [ ] Rapid typing for 10 minutes: bounded memory, one pending task, no extra language model loads, no extension termination.

## macOS

- [ ] Messages, TextEdit, Safari and Chromium-hosted inputs: panel follows caret, never becomes key/main or steals typing focus. No context reads during activation (upstream Chromium deadlock regression).
- [ ] Mouse and Control+1/2 acceptance; custom keys; field/caret moved before click; old request must not apply.
- [ ] Verify UTF-16 replacementRange for emoji/combining sequences, with and without marked text. Converter state must be cleared so accepted text is not reinserted on the next key.
- [ ] Unsupported surrounding text/replacement: candidate is copied only; pasteboard change should be documented to the tester. Full internal-line fallback remains missing.
- [ ] Multiple screens, edges, dark/light, app switching, changing keyboard/input source and Enter reset.
- [ ] No Accessibility permission requirement. NaturalKana provider credentials must not be exposed through unrelated upstream features.

## Real-model acceptance

- [ ] Run all 170 cases for OpenAI fast/quality and Qwen fast/quality, then quality-mode comparison with a distinct judge. Record model IDs, prompt version, region, date, sample counts and rates.
- [ ] Negative pass >=95% without counting transport errors as passes; inspect positive suggestion coverage so an empty-only model cannot appear good.
- [ ] Native review: exact meaning, tense/aspect/negation, politeness and lack of added emotions. Review every synthetic reference initially, not only judge flags.
- [ ] Measure typing pause-to-visible p50/p95 in device UI, including debounce and network. The ~1.5 s p50 target is unverified.
- [ ] Review all prompt examples and 86 seed expressions; trend status must have dated independent source evidence.
- [ ] Enable lexicon refresh in a test repository with configured secrets; verify proposed PR label, no auto-merge, cited source matching and stale expiry.

## Screenshot slots

- [ ] iOS Messages, light/dark: Japanese-only strip + original draft before tap.
- [ ] macOS Messages, light/dark: nonactivating panel above caret.
- [ ] Host onboarding and Keychain-backed settings (redact keys).
- [ ] Standalone preview: screenshot may be regenerated from the supplied app; no fake model output is bundled.
