# Design Brief: `LogAnalyzer`

## Problem

We have structured log files and need a way to parse one and produce an analysis report. Each line of the input file is an independent JSON object with these fields:

- `"timestamp"` — an ISO 8601 datetime string (e.g. `"2024-01-15T14:03:22Z"`)
- `"level"`     — a string such as `"debug"`, `"info"`, `"warn"`, `"error"`
- `"message"`   — a string
- `"metadata"`  — a JSON object (arbitrary key/value pairs)

The deliverable is an Elixir module called `LogAnalyzer` that parses such a file and returns the report described below.

## Constraints

- Use `Jason` for JSON parsing and the standard `DateTime` module for timestamp parsing. No other external dependencies.
- Stream the file line-by-line so the module can handle files larger than memory.
- Timestamps that carry an offset (e.g. `"2024-05-01T01:30:00+02:00"`) must be normalized to UTC before bucketing into `:errors_per_hour`, so a line at `+02:00` 01:30 falls in the `23` hour bucket of the previous UTC day.
- Lines that are blank or contain only whitespace should be skipped silently (they don't count as malformed).
- Error handling rules:
  - If the file does not exist or cannot be opened, return `{:error, reason}`.
  - Every other failure (bad JSON, missing fields, unparseable timestamp) is counted in `:malformed_count`; the line is skipped and processing continues.
  - A line is considered malformed if ANY of these is true:
    - It is not valid JSON
    - The top-level JSON value is not an object
    - Any of `"timestamp"`, `"level"`, `"message"`, or `"metadata"` is absent
    - `"timestamp"` is present but is not a string (e.g. a number or a nested object)
    - `"timestamp"` is a string that cannot be parsed as an ISO 8601 datetime
- Deliver the complete module in a single file.

## Required Interface

1. Provide exactly one public function:

       LogAnalyzer.analyze(path :: String.t()) :: {:ok, report} | {:error, reason}

2. On success, `report` is a plain map with exactly these keys:

   1. `:counts_by_level` — a map from level string to integer count (only levels actually seen in the file appear)
   2. `:error_rate` — a float between 0.0 and 1.0 representing errors / total_valid_lines; 0.0 if no valid lines
   3. `:top_errors` — a list of at most 10 `{message, count}` tuples, taken only from lines whose level is `"error"`, sorted descending by count, then alphabetically by message to break ties
   4. `:time_range` — a `{first_dt, last_dt}` tuple of `DateTime` structs (the earliest and latest timestamps seen across all valid lines); `nil` if no valid lines
   5. `:errors_per_hour` — a map from a `NaiveDateTime`-like label (use a plain `{date, hour}` tuple, e.g. `{{2024,1,15}, 14}`) to integer count of error lines in that UTC hour bucket; only hours that contain at least one error appear
   6. `:malformed_count` — integer count of lines that could not be parsed as valid JSON or were missing any required field or had a non-string timestamp that could not be decoded

## Acceptance Criteria

- `LogAnalyzer.analyze/1` returns `{:ok, report}` on success and `{:error, reason}` when the file does not exist or cannot be opened.
- The returned `report` map contains exactly the six keys above, each carrying the value described.
- `:counts_by_level` includes only levels actually seen in the file.
- `:error_rate` is a float between 0.0 and 1.0 equal to errors / total_valid_lines, and is 0.0 when there are no valid lines.
- `:top_errors` holds at most 10 `{message, count}` tuples drawn only from `"error"`-level lines, sorted descending by count with alphabetical message ordering breaking ties.
- `:time_range` is a `{first_dt, last_dt}` tuple of `DateTime` structs spanning the earliest and latest timestamps across all valid lines, or `nil` when there are no valid lines.
- `:errors_per_hour` maps each `{date, hour}` tuple (e.g. `{{2024,1,15}, 14}`) to the integer count of error lines in that UTC hour bucket, listing only hours with at least one error, with offset timestamps normalized to UTC first (so `+02:00` 01:30 lands in the `23` hour bucket of the previous UTC day).
- `:malformed_count` correctly counts every malformed line per the rules above, while blank/whitespace-only lines are skipped silently and never counted as malformed.
- Malformed lines are skipped and processing continues; only a missing/unopenable file yields `{:error, reason}`.
- The module uses `Jason` and the standard `DateTime` module with no other external dependencies, streams the file line-by-line to handle files larger than memory, and is delivered complete in a single file.
