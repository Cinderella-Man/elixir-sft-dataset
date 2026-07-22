Write me an Elixir module called `Sanitizer` that sanitizes **nested parameter maps** against a declarative schema — think mass-assignment protection plus per-field cleaning for controller params.

The core function is `Sanitizer.sanitize(params, schema)` where `params` is a (possibly deeply nested) map with **string keys** and `schema` describes how to treat each key.

A schema is itself a map with string keys. Each value (a "field spec") is one of:

- An **atom field type**:
  - `:text` — HTML-escape the value and clean it. Strip C0 control characters (except tab `\t`, newline `\n`, carriage return `\r`), trim surrounding whitespace, then escape `&`, `<`, `>`, `"`, and `'` to `&amp;`, `&lt;`, `&gt;`, `&quot;`, and `&#39;` respectively. Always succeeds for binaries; a non-binary is an error (`:not_a_string`).
  - `:identifier` — safe SQL identifier. Keep only `[A-Za-z0-9_]`. If empty after stripping → error `:empty`. If it starts with a digit, prepend `_`. Non-binary → `:not_a_string`.
  - `:filename` — safe filename. Strip null bytes, strip `/` and `\`, keep only `[A-Za-z0-9_.-]`, collapse runs of 2+ dots to a single dot, trim leading/trailing dots. Empty result → `:empty`. Non-binary → `:not_a_string`.
  - `:integer` — accept an integer as-is; accept a binary that parses cleanly to an integer (after trimming); otherwise error `:not_an_integer`.
  - `:boolean` — accept `true`/`false`, or the strings `"true"`/`"false"`; otherwise error `:not_a_boolean`.
- A **`{:list, inner}`** tuple — the value must be a list; apply `inner` (itself a field spec) to every element.
- A **nested schema map** — the value must be a map; recurse.

Rules:

- **Whitelist semantics:** only keys present in the schema survive into the output. Any key in `params` that is not in the schema is dropped.
- **Missing keys:** a schema key with no corresponding key in `params` is simply skipped (not an error, not present in output).
- **Errors:** collect *all* field errors keyed by their **path** (a list of segments — string keys and integer list indices, e.g. `["profile", "handle"]` or `["scores", 1]`). If there are no errors, return `{:ok, cleaned_map}`. If there is at least one error, return `{:error, errors_map}` where `errors_map` maps each failing path to its reason atom.

Also expose `Sanitizer.sql_identifier/1` and `Sanitizer.filename/1` as public helpers returning `{:ok, string}` or `{:error, :empty}`.

Give me the complete module in a single file, standard library only — no external dependencies.