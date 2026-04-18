Write me an Elixir module called `Anonymizer` that takes a list of maps (representing records) and anonymizes specified fields according to configurable rules.

I need this function in the public API:
- `Anonymizer.anonymize(records, rules)` where `records` is a list of maps and `rules` is a map whose keys are field names (atoms) and whose values are one of the following rule atoms or tuples:
  - `:hash` — replace the value with its SHA-256 hex digest
  - `:mask` — keep the first and last character of the string, replace every middle character with `*`. A string of 2 characters should show both with no masking. A string of 1 character should be fully masked as `*`.
  - `:redact` — replace the value with the string `"[REDACTED]"`
  - `{:fake, seed}` — generate a deterministic fake value (a realistic-looking but fabricated string) derived solely from the original value and the given `seed`. The same input value + seed must always produce the same fake output across calls.

The function must return a list of maps of the same length and structure, with the specified fields transformed in place. Fields not mentioned in `rules` must be left untouched.

Referential integrity must be preserved across the entire list: if two records share the same original value for a field, their anonymized outputs for that field must also be identical. This must hold for all four rule types.

Use only the Elixir/OTP standard library — no external dependencies.

Give me the complete module in a single file.