Write me an Elixir module called `Anonymizer` implemented as a **stateful GenServer** that anonymizes streams of records **concurrently** while guaranteeing referential integrity across every batch it has ever processed.

I need these functions in the public API:
- `Anonymizer.start_link(rules)` — start the server. `rules` is a map whose keys are field-name atoms and whose values are one of:
  - `{:pseudonym, prefix}` — replace the value with a stable sequential pseudonym `"<prefix>_<n>"` (e.g. `"PERSON_1"`), where `n` is assigned per field in first-seen order. The same original value always receives the same pseudonym, even across separate `anonymize/2` calls.
  - `:hash` — replace the value with its SHA-256 hex digest.
  - `:redact` — replace the value with `"[REDACTED]"`.
  Returns `{:ok, pid}`.
- `Anonymizer.anonymize(pid, records)` — transform a list of maps and return the transformed list **in the same order**. Records must be processed concurrently (e.g. with `Task.async_stream`), yet the transformation must remain race-free: within and across calls, identical original values for a pseudonymized field must always map to the identical pseudonym, and distinct values must map to distinct pseudonyms. Fields not named in `rules`, and rule fields missing from a given record, are left untouched.
- `Anonymizer.mapping(pid, field)` — return the current `%{original_value => pseudonym}` table accumulated for a pseudonymized `field`.

Because pseudonym numbering depends on first-seen order under concurrency, the exact number attached to any given value is not required to be deterministic across runs — only referential integrity, uniqueness, the `"<prefix>_<n>"` format, and stable cross-batch consistency are required.

Use only the Elixir/OTP standard library — no external dependencies. Give me the complete module in a single file.