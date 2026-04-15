Write me an Elixir module called `LogAnalyzer` that parses a structured log file
and produces an analysis report.

Each line of the input file is an independent JSON object with these fields:
- `"timestamp"` — an ISO 8601 datetime string (e.g. `"2024-01-15T14:03:22Z"`)
- `"level"`     — a string such as `"debug"`, `"info"`, `"warn"`, `"error"`
- `"message"`   — a string
- `"metadata"`  — a JSON object (arbitrary key/value pairs)

I need one public function:

    LogAnalyzer.analyze(path :: String.t()) :: {:ok, report} | {:error, reason}

Where `report` is a plain map with exactly these keys:

- `:counts_by_level`  — a map from level string to integer count
                         (only levels actually seen in the file appear)
- `:error_rate`       — a float between 0.0 and 1.0 representing
                         errors / total_valid_lines; 0.0 if no valid lines
- `:top_errors`       — a list of at most 10 `{message, count}` tuples,
                         taken only from lines whose level is `"error"`,
                         sorted descending by count, then alphabetically
                         by message to break ties
- `:time_range`       — a `{first_dt, last_dt}` tuple of `DateTime` structs
                         (the earliest and latest timestamps seen across
                         all valid lines); `nil` if no valid lines
- `:errors_per_hour`  — a map from a `NaiveDateTime`-like label (use a plain
                         `{date, hour}` tuple, e.g. `{{2024,1,15}, 14}`) to
                         integer count of error lines in that UTC hour bucket;
                         only hours that contain at least one error appear
- `:malformed_count`  — integer count of lines that could not be parsed as
                         valid JSON or were missing any required field or had
                         a non-string timestamp that could not be decoded

Lines that are blank or contain only whitespace should be skipped silently
(they don't count as malformed).

Error handling rules:
- If the file does not exist or cannot be opened, return `{:error, reason}`.
- Every other failure (bad JSON, missing fields, unparseable timestamp)
  is counted in `:malformed_count`; the line is skipped and processing continues.
- A line is considered malformed if ANY of these is true:
  - It is not valid JSON
  - The top-level JSON value is not an object
  - Any of `"timestamp"`, `"level"`, `"message"`, or `"metadata"` is absent
  - `"timestamp"` cannot be parsed as an ISO 8601 datetime

Use `Jason` for JSON parsing and the standard `DateTime` module for timestamp
parsing. No other external dependencies.

Stream the file line-by-line so the module can handle files larger than memory.

Give me the complete module in a single file.