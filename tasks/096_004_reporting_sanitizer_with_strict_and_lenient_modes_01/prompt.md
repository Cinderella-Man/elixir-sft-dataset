Write me an Elixir module called `Sanitizer` that not only cleans input but **reports every transformation it made** and supports a strict mode that *rejects* dirty input instead of silently fixing it.

Every function takes an options keyword list with a `:mode` of either `:lenient` (default) or `:strict`.

Common return contract for each function:
- If cleaning produced **no violations**: `{:ok, cleaned, []}` (in both modes).
- In `:lenient` mode **with** violations: `{:ok, cleaned, violations}` where `violations` is a list of atoms (in a fixed order, see below).
- In `:strict` mode **with** violations: `{:error, violations}`.
- A **hard failure** (empty result) always returns `{:error, [:empty]}` regardless of mode.

Functions:

- `Sanitizer.sql_identifier(input, opts \\ [])` — keep only `[A-Za-z0-9_]`. Violations, in order:
  - `:removed_illegal_chars` — if any character was stripped.
  - `:prefixed_digit_start` — if the cleaned value started with a digit and an underscore was prepended.
  - If the stripped value is empty → `{:error, [:empty]}`.

- `Sanitizer.filename(input, opts \\ [])` — strip null bytes, strip `/` and `\`, keep only `[A-Za-z0-9_.-]`, collapse runs of 2+ dots to one, trim leading/trailing dots. Violations, in order:
  - `:removed_null_bytes` — if the input contained a null byte.
  - `:removed_path_separators` — if the input contained `/` or `\`.
  - `:removed_illegal_chars` — if any other disallowed characters were stripped.
  - `:collapsed_dots` — if a run of 2+ dots was collapsed.
  - `:trimmed_dots` — if leading/trailing dots were trimmed.
  - If the final value is empty → `{:error, [:empty]}`.

- `Sanitizer.text(input, opts \\ [])` — clean free text: strip C0 control characters (except `\t`, `\n`, `\r`), trim surrounding whitespace, then HTML-escape `&`, `<`, `>`, `"`, `'` to `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&#39;` (escape `&` first so the entities you introduce are not re-escaped). Violations, in order:
  - `:removed_control_chars` — if control characters were stripped.
  - `:trimmed_whitespace` — if trimming changed the value.
  - `:escaped_html` — if any character was HTML-escaped.
  - `text` never has a hard failure (an empty result is valid).

Give me the complete module in a single file, standard library only — no external dependencies.
