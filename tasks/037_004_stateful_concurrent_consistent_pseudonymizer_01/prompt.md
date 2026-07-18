Write me an Elixir module called `Anonymizer` implemented as a **stateful GenServer** that anonymizes streams of records **concurrently** while guaranteeing referential integrity across every batch it has ever processed.

I need these functions in the public API:
- `Anonymizer.start_link(rules)` — start the server. `rules` is a map whose keys are field-name atoms and whose values are one of:
  - `{:pseudonym, prefix}` — replace the value with a stable sequential pseudonym `"<prefix>_<n>"` (e.g. `"PERSON_1"`), where `n` is assigned per field in first-seen order starting at 1. The same original value always receives the same pseudonym, even across separate `anonymize/2` calls.
  - `:hash` — replace the value with the **lowercase** SHA-256 hex digest of its string form.
  - `:redact` — replace the value with `"[REDACTED]"`.
  Returns `{:ok, pid}`.
- `Anonymizer.anonymize(pid, records)` — transform a list of maps and return the transformed list **in the same order**. Records must be processed concurrently (e.g. with `Task.async_stream`), yet the transformation must remain race-free: within and across calls, identical original values for a pseudonymized field must always map to the identical pseudonym, and distinct values must map to distinct pseudonyms. Distinctness is by the original value itself (not a stringified copy), so e.g. the integer `42` and the string `"42"` are different values and receive different pseudonyms. Fields not named in `rules`, and rule fields missing from a given record, are left untouched (and missing rule fields are not added to the record).
- `Anonymizer.mapping(pid, field)` — return the current `%{original_value => pseudonym}` table accumulated for a pseudonymized `field`, keyed by the original values themselves. Returns an empty map (`%{}`) if no values have been seen for that field yet.

Because pseudonym numbering depends on first-seen order under concurrency, the exact number attached to any given value is not required to be deterministic across runs — only referential integrity, uniqueness, the `"<prefix>_<n>"` format, and stable cross-batch consistency are required. Each pseudonymized field numbers independently using its own prefix.

Use only the Elixir/OTP standard library — no external dependencies. Give me the complete module in a single file.
