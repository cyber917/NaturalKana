# Design notes

- Preserve the azooKey kana/kanji converter; phrasing suggestions use a separate provider client and candidate UI.
- Suggestions require explicit consent and a provider key. Defaults are disabled, five candidates, a 600 ms pause and a daily cap of 200 requests. The candidate limit is adjustable from 1 to 10.
- Provider calls use HTTPS, structured output, a 20-second timeout and an output-token budget based on the candidate limit. Drafts and responses are not written to diagnostics. Model IDs are configured by the user.
- Language and protected-field checks run locally before requesting suggestions. Language detection is heuristic and may reject unusual mixed-script input.
- Cache entries exist only in memory. Changes to settings, credentials or personal vocabulary invalidate them. Duplicate pending requests are coalesced; changed drafts cancel stale requests.
- iOS replacement is limited to available context at the end of the input field. Candidates have a fixed-height panel with horizontal paging and vertical scrolling for long text.
- macOS keyboard acceptance uses a verified replacement range. Palette clicks copy the suggestion when the host replacement cannot be verified safely.
- Personal vocabulary is separate from kana conversion dictionaries. Only matching terms, meanings and usage notes are sent as bounded reference data. Seed vocabulary is unverified until reviewed.
- Optional quality mode runs two generation calls, then a judge that selects existing candidates. It reserves up to three requests and has no measured quality advantage yet.
- The macOS converter uses dictionary conversion because the neural Metal backend failed during native typing tests. Neural conversion requires additional compatibility testing.
- Public sources contain fixed upstream revisions and portable patches. Local identities, signing material, personal vocabulary and built apps are ignored by Git.
- The MIT license covers original additions. Model and data licenses require separate review before distributing packaged applications. See THIRD_PARTY_NOTICES.md.
