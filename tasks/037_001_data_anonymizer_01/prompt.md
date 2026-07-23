# `Anonymizer` — field anonymization for record lists

Implement an Elixir module `Anonymizer` that anonymizes specified fields in a list of maps (records) according to configurable rules. Single file, complete module.

**Public API**
- `Anonymizer.anonymize(records, rules)` — `records` is a list of maps; `rules` is a map whose keys are field names (atoms) and whose values are one of the rule atoms or tuples below.

**Rules**
- `:hash` — replace the value with its SHA-256 hex digest, encoded as a lowercase hexadecimal string.
- `:mask` — keep the first and last character of the string, replace every middle character with `*`. A 2-character string shows both characters with no masking. A 1-character string is fully masked as `*`.
- `:redact` — replace the value with the string `"[REDACTED]"`.
- `{:fake, seed}` — generate a deterministic fake value (a realistic-looking but fabricated string) derived solely from the original value and the given `seed`. The same input value + seed must always produce the same fake output across calls.

**Return shape**
- Return a list of maps of the same length and structure, with the specified fields transformed in place.
- Fields not mentioned in `rules` must be left untouched.
- If a record does not contain a field named in `rules`, skip that field gracefully for that record — do not add the missing key.

**Referential integrity**
- Preserve across the entire list: if two records share the same original value for a field, their anonymized outputs for that field must also be identical.
- This must hold for all four rule types.

**Constraints**
- Use only the Elixir/OTP standard library — no external dependencies.
- Deliver the complete module in a single file.
