Write me an Elixir module called `MaskingServer` — a `GenServer` that scrubs sensitive data from log-bound maps, keyword lists, and strings for concurrent callers, supports registering **extra masking patterns at runtime**, and tracks cumulative masking statistics.

I need these functions in the public API:

- `MaskingServer.start_link(opts)` — starts the server. `opts` is a keyword list; `opts[:sensitive_keys]` is a list of atoms and/or strings (defaulting to `[]` when absent). Key comparison during masking must be case-insensitive and work for both atom and string keys. Returns `{:ok, pid}`.

- `MaskingServer.mask(server, data)` — a synchronous call that accepts a map, a keyword list, a plain list, or any other term and returns the same shape with sensitive data scrubbed.
  - Maps and keyword lists are walked recursively. If a key matches a configured sensitive key, its value is replaced with `"[MASKED]"` regardless of the value's type. Non-sensitive keys are preserved and their values continue to be walked.
  - Plain lists (including lists of maps or keyword lists) are walked element-by-element.
  - Every **string value** encountered under a non-sensitive key is passed through the same pattern scrubbing as `mask_string/2`. Values replaced with `"[MASKED]"` because of a sensitive key are **not** additionally pattern-scanned.
  - Structs, numbers, atoms, and other terms are returned unchanged.

- `MaskingServer.mask_string(server, string)` — a synchronous call that scans a raw string and masks the built-in patterns plus any registered custom patterns (see `add_pattern/3`), returning the scrubbed string. The built-in patterns are:
  - **Credit card numbers**: any sequence of 13–19 digits (optionally separated by single spaces or hyphens) — replace every digit except the last 4 with `*`, keeping separators intact. E.g. `"4111-1111-1111-1234"` → `"****-****-****-1234"`.
  - **Email addresses**: keep only the first character of the local part and replace the rest with `***`. E.g. `"john.doe@example.com"` → `"j***@example.com"`.
  - **SSN patterns**: sequences matching `\d{3}-\d{2}-\d{4}` — replace with `"***-**-****"`.

- `MaskingServer.add_pattern(server, regex, replacement)` — registers an additional masking pattern where `regex` is a compiled `Regex` and `replacement` is a string. Returns `:ok`. When scrubbing a string, the built-in patterns are applied first (credit cards, then SSNs, then emails), and then every registered custom pattern is applied in the order it was added, each via a standard regex replace with its replacement string. Registered patterns apply to every subsequent string scrubbed by both `mask_string/2` and `mask/2`.

- `MaskingServer.stats(server)` — returns a map `%{keys_masked: k, patterns_applied: p}` describing cumulative work since the server started:
  - `:keys_masked` — the total number of values replaced with `"[MASKED]"` because their key was sensitive, summed across every `mask/2` call.
  - `:patterns_applied` — the total number of pattern matches replaced (built-in **and** custom patterns) across every string scrubbed by every `mask/2` and `mask_string/2` call.

Because all operations go through the `GenServer`, concurrent callers are serialized and the statistics stay exact under concurrency.

Give me the complete module in a single file. Use only the Elixir standard library and built-in regex support — no external dependencies.