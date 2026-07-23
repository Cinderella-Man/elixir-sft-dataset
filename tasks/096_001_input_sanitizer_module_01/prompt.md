# Specification: `Sanitizer` — Input Cleaning and Validation Module

## Overview

This document specifies an Elixir module named `Sanitizer` whose purpose is to clean and validate user inputs against common injection and traversal attacks. The module exposes three public functions, detailed below.

The deliverable is the complete module in a single file with no external dependencies — standard library only. No external HTML parsing libraries may be used; tag stripping is to be implemented with regex or hand-rolled parsing.

## API

### `Sanitizer.html(input, opts \\ [])`

Strips all HTML tags except those in an allowlist. The default allowlist is `["b", "i", "em", "strong", "a"]`. The allowlist is configurable via an `:allow` option (e.g., `allow: ["b", "span"]`).

Rules:

- All attributes are stripped from every tag **except** `href` on `<a>` tags.
- Any `href` value that starts with `javascript:` (case-insensitive, ignoring whitespace) must be removed entirely — the `<a>` is replaced with just its inner text content.
- Tags not in the allowlist are stripped but their inner text content is preserved — **except** raw-content tags (`<script>`, `<style>`, `<noscript>`, `<iframe>`), whose entire inner content is dropped along with the tag (e.g. `<script>alert(1)</script>` sanitizes to `""`).
- The function returns the sanitized string.

### `Sanitizer.sql_identifier(input)`

Ensures a string is safe for interpolation as a SQL identifier (e.g. a table or column name).

Rules:

- Any character that is not alphanumeric or an underscore is removed (stripped out) — dropped characters are deleted, not replaced with a placeholder.
- If the result is empty, the function returns `{:error, :empty}`.
- If the result starts with a digit, an underscore is prepended.
- On success the function returns `{:ok, sanitized}`.

### `Sanitizer.filename(input)`

Produces a safe filename.

Rules:

- Null bytes (`\0`) are stripped.
- Path traversal sequences are stripped: `..`, `/`, `\`.
- Any character outside of alphanumerics, underscores, hyphens, and dots is stripped or replaced.
- Multiple consecutive dots are collapsed into a single dot.
- After collapsing, any leading and trailing dots are stripped.
- If the result is empty after sanitization, the function returns `{:error, :empty}`.
- On success the function returns `{:ok, sanitized}`.

## Edge cases

- **Unclosed raw-content tags.** The raw-content dropping rule holds even when the closing tag is missing entirely: the raw content is dropped to the END of the input (`safe<script>alert(1)` sanitizes to `"safe"`).
- **Traversal remnants in filenames.** A traversal remnant like `.etcpasswd` becomes `etcpasswd`.
- **Dotfiles.** Because leading dots are stripped, a legitimate dotfile name like `.gitignore` therefore comes back as `gitignore`.
