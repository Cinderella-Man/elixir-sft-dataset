# Ticket: Implement `AccessLogAnalyzer` — HTTP access log traffic analysis

Build an Elixir module `AccessLogAnalyzer` that parses a structured HTTP access log file and produces a traffic analysis report. Each input line is an independent JSON object.

**Input line fields (per JSON object):**
- `"timestamp"` — an ISO 8601 datetime string (e.g. `"2024-01-15T14:03:22Z"`).
- `"method"` — an HTTP method string (e.g. `"GET"`, `"POST"`).
- `"path"` — a string representing the request path (e.g. `"/api/users"`).
- `"status_code"` — an integer HTTP status code (e.g. `200`, `404`, `500`).
- `"duration_ms"` — a number (integer or float) representing response time in milliseconds.

**Public API:**
- Exactly one public function: `AccessLogAnalyzer.analyze(path :: String.t()) :: {:ok, report} | {:error, reason}`.
- `report` is a plain map with exactly the keys listed below.

**Report keys:**
- `:requests_by_method` — a map from method string to integer count; only methods actually seen appear.
- `:requests_by_status` — a map from status code integer to integer count; only status codes actually seen appear.
- `:top_paths` — a list of at most 10 `{path, count}` tuples, sorted descending by count, then alphabetically by path to break ties.
- `:avg_duration` — float average `duration_ms` across all valid lines; `0.0` if no valid lines.
- `:max_duration` — the single `{path, duration_ms}` tuple with the highest duration; `nil` if no valid lines; if multiple lines tie, keep the one whose path is alphabetically first.
- `:error_rate` — float between `0.0` and `1.0` representing lines with `status_code >= 400` divided by total valid lines; `0.0` if no valid lines.
- `:requests_per_minute` — a map from a `{date_tuple, {hour, minute}}` tuple (e.g. `{{2024,1,15}, {14, 3}}`) to integer count; only minutes with at least one request appear.
- `:time_range` — a `{first_dt, last_dt}` tuple of `DateTime` structs; `nil` if no valid lines.
- `:malformed_count` — integer count of lines that could not be parsed.

**Line skipping:**
- Blank or whitespace-only lines are skipped silently and do NOT count as malformed.

**Error handling:**
- If the file does not exist or cannot be opened, return `{:error, reason}`.
- Every other failure (bad JSON, missing fields, wrong types) is counted in `:malformed_count`; the line is skipped and processing continues.
- A line is malformed if ANY of these is true:
  - It is not valid JSON.
  - The top-level JSON value is not an object.
  - Any of `"timestamp"`, `"method"`, `"path"`, `"status_code"`, or `"duration_ms"` is absent.
  - `"timestamp"` cannot be parsed as an ISO 8601 datetime.
  - `"method"` or `"path"` is not a string.
  - `"status_code"` is not an integer.
  - `"duration_ms"` is not a number (integer or float).

**Constraints:**
- Use `Jason` for JSON parsing and the standard `DateTime` module for timestamp parsing. No other external dependencies.
- Stream the file line-by-line so the module can handle files larger than memory.

**Deliverable:**
- The complete module in a single file.
