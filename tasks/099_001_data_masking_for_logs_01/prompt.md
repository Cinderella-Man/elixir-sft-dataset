Write me an Elixir module called `LogMasker` that scrubs sensitive data from log-bound maps, keyword lists, and strings.

I need these functions in the public API:
- `LogMasker.new(sensitive_keys)` which creates a masker configuration. `sensitive_keys` is a list of atoms (e.g. `[:password, :ssn, :credit_card, :token]`). Return an opaque struct or map that can be passed to other functions.
- `LogMasker.mask(masker, data)` which accepts either a map, a keyword list, or a string, and returns the same type with sensitive data scrubbed. For maps and keyword lists, recursively walk all values — if a key matches a sensitive key (comparison should be case-insensitive and work for both atom and string keys), replace its value with `"[MASKED]"` regardless of what the value is. Lists of maps or keyword lists should also be walked recursively. Non-sensitive keys must be left completely untouched.
- `LogMasker.mask_string(masker, string)` which scans a raw string and masks three patterns:
  - **Credit card numbers**: any sequence of 13–19 digits (optionally separated by spaces or hyphens) — replace all digit groups except the last 4 digits with `*` characters of equal length, keeping separators intact. E.g. `"4111-1111-1111-1234"` → `"****-****-****-1234"`.
  - **Email addresses**: mask the local part (before `@`) keeping only the first character and replacing the rest with `***`. E.g. `"john.doe@example.com"` → `"j***@example.com"`.
  - **SSN patterns**: sequences matching `\d{3}-\d{2}-\d{4}` — replace with `"***-**-****"`.

`LogMasker.mask/2` should also apply `mask_string/2` to any string *values* it encounters while walking a map or keyword list, even for non-sensitive keys, so stray PII embedded in strings is caught everywhere.

Give me the complete module in a single file. Use only the Elixir standard library and built-in regex support — no external dependencies.