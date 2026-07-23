# Ticket: `Sanitizer` — schema-driven nested params sanitizer

**Summary:** Implement an Elixir module `Sanitizer` that sanitizes nested parameter maps against a declarative schema (mass-assignment protection plus per-field cleaning for controller params). Single file, standard library only, no external dependencies.

**Entry point**

- `Sanitizer.sanitize(params, schema)` is the core function.
- `params` is a possibly deeply nested map with **string keys**.
- `schema` describes how to treat each key; it is itself a map with string keys.
- Each schema value is a "field spec": an atom field type, a `{:list, inner}` tuple, or a nested schema map.

**Field spec — atom field types**

- `:text` — HTML-escape the value and clean it. Strip C0 control characters except tab `\t`, newline `\n`, carriage return `\r`; trim surrounding whitespace; then escape `&`, `<`, `>`, `"`, and `'` to `&amp;`, `&lt;`, `&gt;`, `&quot;`, and `&#39;` respectively. Always succeeds for binaries. Non-binary → error `:not_a_string`.
- `:identifier` — safe SQL identifier. Keep only `[A-Za-z0-9_]`. Empty after stripping → error `:empty`. If the result starts with a digit, prepend `_`. Non-binary → `:not_a_string`.
- `:filename` — safe filename. Strip null bytes; strip `/` and `\`; keep only `[A-Za-z0-9_.-]`; collapse runs of 2+ dots to a single dot; trim leading/trailing dots. Empty result → `:empty`. Non-binary → `:not_a_string`.
- `:integer` — accept an integer as-is; accept a binary that parses cleanly to an integer after trimming; otherwise error `:not_an_integer`.
- `:boolean` — accept `true`/`false`, or the strings `"true"`/`"false"`; otherwise error `:not_a_boolean`.

**Field spec — composite types**

- `{:list, inner}` — value must be a list; apply `inner` (itself a field spec) to every element.
- Nested schema map — value must be a map; recurse.

**Key selection**

- Whitelist semantics: only keys present in the schema survive into the output. Any key in `params` not in the schema is dropped.
- Missing keys: a schema key with no corresponding key in `params` is skipped — not an error, not present in output.

**Error reporting**

- Collect *all* field errors, keyed by **path**: a list of segments made of string keys and integer list indices, e.g. `["profile", "handle"]` or `["scores", 1]`.
- No errors → return `{:ok, cleaned_map}`.
- At least one error → return `{:error, errors_map}`, where `errors_map` maps each failing path to its reason atom.

**Type-shape mismatches**

- Nested schema map expected but value is not a map → `:expected_map` at that field's path.
- `{:list, inner}` spec given a non-list value → `:expected_list`.
- `sanitize(%{"profile" => "nope"}, %{"profile" => %{"bio" => :text}})` returns `{:error, %{["profile"] => :expected_map}}`.
- `sanitize(%{"tags" => "nope"}, %{"tags" => {:list, :text}})` returns `{:error, %{["tags"] => :expected_list}}`.

**Public helpers**

- Expose `Sanitizer.sql_identifier/1` and `Sanitizer.filename/1`, each returning `{:ok, string}` or `{:error, :empty}`.

**Deliverable**

- The complete module in a single file.
