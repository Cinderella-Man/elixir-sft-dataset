# FieldMasker — Per-Field Masking Strategies

## Overview

`FieldMasker` is a single-file Elixir module that scrubs sensitive data out of log-bound maps, keyword lists, and strings. Its defining characteristic is that **each sensitive key is masked according to its own strategy**, rather than every sensitive value being blanked identically.

The implementation must be delivered as one complete module in a single file. It may rely only on the Elixir standard library and built-in support (`:crypto`, regex) — no external dependencies.

## API

The module exposes three public functions.

### `FieldMasker.new(policies)`

Creates a masker configuration. `policies` is either a map or a keyword list mapping a key (atom and/or string) to a masking strategy. Key comparison at mask time must be case-insensitive and must work for both atom and string keys. The function returns an opaque struct or map suitable for passing to the other functions.

The valid strategies are:

- `:redact` — replaces the value with the string `"[MASKED]"` regardless of the value's type.
- `:last4` — for a string value, keeps the last 4 characters and replaces every earlier character with a single `*` (so `"4111111111111234"` → `"************1234"`). When the string has 4 or fewer characters, every character is replaced with a `*` (so `"ab"` → `"**"` and `""` → `""`). When the value is **not** a string, it is replaced with `"[MASKED]"`.
- `:hash` — replaces the value with `"sha256:"` followed by the lowercase hex SHA-256 digest of the value. The value itself is used when it is a string; otherwise its `inspect/1` representation is used. For example, the masked value for `"hunter2"` is `"sha256:"` concatenated with `Base.encode16(:crypto.hash(:sha256, "hunter2"), case: :lower)`.

### `FieldMasker.mask(masker, data)`

Accepts a map, a keyword list, a plain list, or any other term, and returns the same shape with sensitive data scrubbed.

- Maps and keyword lists are walked recursively. If a key appears in `policies`, its value is replaced by applying that key's strategy (as described above). Non-policy keys are preserved and their values continue to be walked.
- Plain lists (including lists of maps or keyword lists) are walked element-by-element.
- Every **string value** encountered under a key that is **not** in `policies` is passed through the same pattern scrubbing as `mask_string/2` (described below), so stray PII in free text is still caught. A value transformed by a strategy is **not** additionally pattern-scanned.
- Structs, numbers, atoms, and other terms with no matching policy key are returned unchanged.

### `FieldMasker.mask_string(masker, string)`

Scans a raw string and masks these three patterns:

- **Credit card numbers**: any sequence of 13–19 digits (optionally separated by single spaces or hyphens) — every digit except the last 4 is replaced with `*`, keeping separators intact. E.g. `"4111-1111-1111-1234"` → `"****-****-****-1234"`.
- **Email addresses**: only the first character of the local part is kept, and the rest is replaced with the literal `***`. Exactly `***` is always appended after the first character. E.g. `"john.doe@example.com"` → `"j***@example.com"`.
- **SSN patterns**: sequences matching `\d{3}-\d{2}-\d{4}` are replaced with `"***-**-****"`.

## Edge cases

- Under `:last4`, a string of 4 or fewer characters has every character replaced with a `*`: `"ab"` → `"**"`, and `""` → `""`.
- Under `:last4`, a non-string value becomes `"[MASKED]"`.
- Under `:redact`, the replacement with `"[MASKED]"` happens regardless of the value's type.
- Under `:hash`, non-string values are hashed via their `inspect/1` representation.
- Email masking appends `***` even when the local part is a single character, so `"x@example.com"` → `"x***@example.com"`.
- Policy key matching is case-insensitive and applies to both atom and string keys.
- A value already transformed by a strategy is not run through pattern scanning a second time.
