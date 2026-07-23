# Design brief: `LogMasker`

## Problem

Log-bound payloads in our system arrive as maps, keyword lists, and raw strings, and they routinely carry sensitive data — passwords, tokens, SSNs, credit card numbers, email addresses. We need a single Elixir module, `LogMasker`, that scrubs sensitive data from log-bound maps, keyword lists, and strings before they reach the log sink.

## Constraints

- Deliver the complete module in a single file.
- Use only the Elixir standard library and built-in regex support — no external dependencies.

## Required interface

1. **`LogMasker.new(sensitive_keys)`** — creates a masker configuration. `sensitive_keys` is a list of atoms (e.g. `[:password, :ssn, :credit_card, :token]`). Return an opaque struct or map that can be passed to the other functions.

2. **`LogMasker.mask(masker, data)`** — accepts either a map, a keyword list, or a string, and returns the same type with sensitive data scrubbed.
   - For maps and keyword lists, recursively walk all values. If a key matches a sensitive key (comparison should be case-insensitive and work for both atom and string keys), replace its value with `"[MASKED]"` regardless of what the value is.
   - Lists of maps or keyword lists should also be walked recursively.
   - Non-sensitive keys must be left completely untouched.

3. **`LogMasker.mask_string(masker, string)`** — scans a raw string and masks three patterns:
   1. **Credit card numbers**: any sequence of 13–19 digits (optionally separated by spaces or hyphens) — replace all digit groups except the last 4 digits with `*` characters of equal length, keeping separators intact. E.g. `"4111-1111-1111-1234"` → `"****-****-****-1234"`.
   2. **Email addresses**: mask the local part (before `@`) keeping only the first character and replacing the rest with `***`. E.g. `"john.doe@example.com"` → `"j***@example.com"`. A single-character local part like `"a@b.com"` becomes `"a***@b.com"`.
   3. **SSN patterns**: sequences matching `\d{3}-\d{2}-\d{4}` — replace with `"***-**-****"`.

   Mask SSN patterns before applying the credit-card pattern, so that two adjacent SSNs are each replaced independently rather than being consumed as one long credit-card number. E.g. `"123-45-6789 987-65-4321"` → `"***-**-**** ***-**-****"` (no trailing digits left visible).

4. **Cross-cutting behavior of `LogMasker.mask/2`** — it should also apply `mask_string/2` to any string *values* it encounters while walking a map or keyword list, even for non-sensitive keys, so stray PII embedded in strings is caught everywhere. A masker built from an empty `sensitive_keys` list therefore masks nothing by key, but still pattern-masks string values it encounters.

## Acceptance criteria

- `LogMasker.new/1` returns a configuration value (opaque struct or map) accepted by the other functions.
- Given a map or keyword list, `LogMasker.mask/2` returns the same type, with every sensitive-key value replaced by `"[MASKED]"` whatever that value was, matching keys case-insensitively across both atom and string keys, and recursing through nested maps, nested keyword lists, and lists of maps or keyword lists.
- Values under non-sensitive keys are otherwise left completely untouched, aside from string values, which are passed through `mask_string/2`.
- Given a string, `LogMasker.mask/2` returns a string.
- `LogMasker.mask_string/2` yields `"****-****-****-1234"` for `"4111-1111-1111-1234"`, `"j***@example.com"` for `"john.doe@example.com"`, `"a***@b.com"` for `"a@b.com"`, `"***-**-****"` for any `\d{3}-\d{2}-\d{4}` match, and `"***-**-**** ***-**-****"` for `"123-45-6789 987-65-4321"`.
- Credit-card masking covers digit sequences of 13–19 digits with optional space or hyphen separators, preserves those separators, preserves the last 4 digits, and replaces each other digit group with an equal-length run of `*`.
- An empty `sensitive_keys` list masks nothing by key while still pattern-masking encountered string values.
- The module compiles and runs against the Elixir standard library and built-in regex support alone, in one file.
