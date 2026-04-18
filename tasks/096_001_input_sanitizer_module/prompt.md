Write me an Elixir module called `Sanitizer` that cleans and validates user inputs against common injection and traversal attacks.

I need these functions in the public API:

- `Sanitizer.html(input, opts \\ [])` which strips all HTML tags except those in an allowlist. The default allowlist is `["b", "i", "em", "strong", "a"]`. The allowlist is configurable via an `:allow` option (e.g., `allow: ["b", "span"]`). Rules:
  - All attributes are stripped from every tag **except** `href` on `<a>` tags.
  - Any `href` value that starts with `javascript:` (case-insensitive, ignoring whitespace) must be removed entirely — replace the `<a>` with just its inner text content.
  - Tags not in the allowlist are stripped but their inner text content is preserved.
  - Return the sanitized string.

- `Sanitizer.sql_identifier(input)` which ensures a string is safe for interpolation as a SQL identifier (e.g. a table or column name). Rules:
  - Strip or replace any character that is not alphanumeric or an underscore.
  - If the result is empty, return `{:error, :empty}`.
  - If the result starts with a digit, prepend an underscore.
  - Return `{:ok, sanitized}` on success.

- `Sanitizer.filename(input)` which produces a safe filename. Rules:
  - Strip null bytes (`\0`).
  - Strip path traversal sequences: `..`, `/`, `\`.
  - Strip or replace any character outside of alphanumerics, underscores, hyphens, and dots.
  - Collapse multiple consecutive dots into a single dot.
  - If the result is empty after sanitization, return `{:error, :empty}`.
  - Return `{:ok, sanitized}` on success.

Give me the complete module in a single file with no external dependencies — standard library only. Do not use any external HTML parsing libraries; implement the tag stripping with regex or hand-rolled parsing.