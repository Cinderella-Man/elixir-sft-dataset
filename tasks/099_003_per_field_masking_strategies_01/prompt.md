Write me an Elixir module called `FieldMasker` that scrubs sensitive data from log-bound maps, keyword lists, and strings, where **each sensitive key is masked according to its own strategy** rather than every sensitive value being blanked identically.

I need these functions in the public API:

- `FieldMasker.new(policies)` — creates a masker configuration. `policies` is either a map or a keyword list mapping a key (atom and/or string) to a masking strategy. Comparison at mask time must be case-insensitive and work for both atom and string keys. Return an opaque struct or map that can be passed to the other functions. The valid strategies are:
  - `:redact` — replace the value with the string `"[MASKED]"` regardless of its type.
  - `:last4` — for a string value, keep the last 4 characters and replace every earlier character with a single `*` (so `"4111111111111234"` → `"************1234"`); if the string has 4 or fewer characters, replace every character with a `*` (so `"ab"` → `"**"` and `""` → `""`); if the value is **not** a string, replace it with `"[MASKED]"`.
  - `:hash` — replace the value with `"sha256:"` followed by the lowercase hex SHA-256 digest of the value. Use the value itself when it is a string; otherwise use its `inspect/1` representation. For example the masked value for `"hunter2"` is `"sha256:"` concatenated with `Base.encode16(:crypto.hash(:sha256, "hunter2"), case: :lower)`.

- `FieldMasker.mask(masker, data)` — accepts a map, a keyword list, a plain list, or any other term, and returns the same shape with sensitive data scrubbed.
  - Maps and keyword lists are walked recursively. If a key appears in `policies`, its value is replaced by applying that key's strategy (as described above). Non-policy keys are preserved and their values continue to be walked.
  - Plain lists (including lists of maps or keyword lists) are walked element-by-element.
  - Every **string value** encountered under a key that is **not** in `policies` is passed through the same pattern scrubbing as `mask_string/2` (see below), so stray PII in free text is still caught. A value transformed by a strategy is **not** additionally pattern-scanned.
  - Structs, numbers, atoms, and other terms with no matching policy key are returned unchanged.

- `FieldMasker.mask_string(masker, string)` — scans a raw string and masks these three patterns:
  - **Credit card numbers**: any sequence of 13–19 digits (optionally separated by single spaces or hyphens) — replace every digit except the last 4 with `*`, keeping separators intact. E.g. `"4111-1111-1111-1234"` → `"****-****-****-1234"`.
  - **Email addresses**: keep only the first character of the local part and replace the rest with the literal `***`. Always append exactly `***` after the first character — even when the local part is a single character (so `"x@example.com"` → `"x***@example.com"`). E.g. `"john.doe@example.com"` → `"j***@example.com"`.
  - **SSN patterns**: sequences matching `\d{3}-\d{2}-\d{4}` — replace with `"***-**-****"`.

Give me the complete module in a single file. Use only the Elixir standard library and built-in (`:crypto`, regex) support — no external dependencies.
