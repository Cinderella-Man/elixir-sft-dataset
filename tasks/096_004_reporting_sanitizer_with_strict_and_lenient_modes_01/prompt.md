Implement `Sanitizer` — an Elixir module that cleans input, reports every transformation it made, and supports a strict mode that rejects dirty input instead of silently fixing it.

**Options**
- Every function takes an options keyword list as its final argument.
- The keyword list carries a `:mode` key of either `:lenient` (the default) or `:strict`.

**Common return contract (all functions)**
- Cleaning produced no violations: `{:ok, cleaned, []}` — in both modes.
- `:lenient` mode with violations: `{:ok, cleaned, violations}`, where `violations` is a list of atoms in the fixed order specified per function below.
- `:strict` mode with violations: `{:error, violations}`.
- Hard failure (empty result): always `{:error, [:empty]}`, regardless of mode.

**`Sanitizer.sql_identifier(input, opts \\ [])`**
- Keep only `[A-Za-z0-9_]`.
- Violations, in this order:
  - `:removed_illegal_chars` — any character was stripped.
  - `:prefixed_digit_start` — the cleaned value started with a digit and an underscore was prepended.
- Stripped value is empty → `{:error, [:empty]}`.

**`Sanitizer.filename(input, opts \\ [])`**
- Strip null bytes; strip `/` and `\`; keep only `[A-Za-z0-9_.-]`; collapse runs of 2+ dots to one; trim leading/trailing dots.
- Violations, in this order:
  - `:removed_null_bytes` — the input contained a null byte.
  - `:removed_path_separators` — the input contained `/` or `\`.
  - `:removed_illegal_chars` — any other disallowed characters were stripped.
  - `:collapsed_dots` — a run of 2+ dots was collapsed.
  - `:trimmed_dots` — leading/trailing dots were trimmed.
- Final value is empty → `{:error, [:empty]}`.

**`Sanitizer.text(input, opts \\ [])`**
- Clean free text: strip C0 control characters except `\t`, `\n`, `\r`; trim surrounding whitespace; then HTML-escape `&`, `<`, `>`, `"`, `'` to `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&#39;`. Escape `&` first so the introduced entities are not re-escaped.
- Violations, in this order:
  - `:removed_control_chars` — control characters were stripped.
  - `:trimmed_whitespace` — trimming changed the value.
  - `:escaped_html` — any character was HTML-escaped.
- `text` never has a hard failure; an empty result is valid.

**Deliverable**
- Complete module in a single file.
- Standard library only — no external dependencies.
