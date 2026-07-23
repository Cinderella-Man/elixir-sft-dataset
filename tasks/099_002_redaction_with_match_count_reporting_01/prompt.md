# Specification — `LogRedactor`: Redaction With Match-Count Reporting

## Overview

This document specifies an Elixir module named `LogRedactor` that scrubs sensitive data from log-bound maps, keyword lists, and strings **and reports how much it scrubbed**. The module follows the same idea as a basic log masker, with one addition: every operation must hand back a *redaction report*, so that callers can emit metrics about how much PII a payload contained.

## Public API

The module exposes the following three functions.

### `LogRedactor.new(sensitive_keys)`

Creates a redactor configuration. `sensitive_keys` is a list of atoms and/or strings (e.g. `[:password, :ssn, :token]`). Comparison at redaction time must be case-insensitive and work for both atom and string keys. The function returns an opaque struct or map that can be passed to the other functions.

### `LogRedactor.redact(redactor, data)`

Accepts a map, a keyword list, a plain list, or any other term, and returns a **tuple** `{scrubbed, report}`.

- `scrubbed` is the same shape as the input with sensitive data removed.
- Maps and keyword lists are walked recursively. If a key matches a sensitive key, its value is replaced with the string `"[REDACTED]"` regardless of the value's type (integer, nil, list, string, …). Non-sensitive keys are preserved, and their values continue to be walked.
- Plain lists (including lists of maps or keyword lists) are walked element-by-element.
- Every **string value** encountered under a non-sensitive key is passed through the same pattern scrubbing as `redact_string/2` (described below), so that stray PII embedded in free text is caught everywhere. Values replaced with `"[REDACTED]"` because of a sensitive key are **not** additionally pattern-scanned.
- Structs, numbers, atoms, and other terms are returned unchanged.

### `LogRedactor.redact_string(redactor, string)`

Scans a raw string, masks the three patterns described below, and returns `{scrubbed_string, report}`. The report has the same four keys; `:keys_masked` is always `0` for this function, and the other three count how many matches of each pattern were masked in the string.

## Report structure

`report` is a map with exactly these four integer keys:

- `:keys_masked` — how many values were replaced with `"[REDACTED]"` because their key was sensitive (counted across the whole recursive walk).
- `:credit_cards` — how many credit-card matches were masked across all scanned strings.
- `:emails` — how many email matches were masked across all scanned strings.
- `:ssns` — how many SSN matches were masked across all scanned strings.

## String patterns

Three patterns are scrubbed, using scrubbing rules identical to those of a standard masker.

- **Credit card numbers**: any sequence of 13–19 digits (optionally separated by single spaces or hyphens) — every digit except the last 4 is replaced with a `*`, keeping separators intact. E.g. `"4111-1111-1111-1234"` → `"****-****-****-1234"`.
- **Email addresses**: only the first character of the local part (before `@`) is kept, and the rest is replaced with `***`. E.g. `"john.doe@example.com"` → `"j***@example.com"`.
- **SSN patterns**: sequences matching `\d{3}-\d{2}-\d{4}` are replaced with `"***-**-****"`.

## Edge cases

- For an input with nothing to scrub (e.g. an empty map), the report is `%{keys_masked: 0, credit_cards: 0, emails: 0, ssns: 0}`.
- Sensitive-key matching is case-insensitive and applies to atom keys and string keys alike.
- A value masked as `"[REDACTED]"` due to a sensitive key is never scanned again for the three string patterns.
- Values of any type (integer, nil, list, string, …) under a sensitive key become `"[REDACTED]"`.
- Structs, numbers, atoms, and other terms pass through unchanged.

## Delivery constraints

The complete module is delivered in a single file. Only the Elixir standard library and built-in regex support may be used — no external dependencies.
