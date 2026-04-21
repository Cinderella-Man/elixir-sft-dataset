Write me an Elixir module called `MetricAggregator` that parses a structured
metrics file and produces a statistical summary report.

Each line of the input file is an independent JSON object with these fields:
- `"timestamp"` — an ISO 8601 datetime string (e.g. `"2024-01-15T14:03:22Z"`)
- `"name"`      — a non-empty string identifying the metric (e.g. `"cpu_usage"`)
- `"value"`     — a number (integer or float)
- `"tags"`      — a JSON object of string key/value pairs (arbitrary)

I need one public function:

    MetricAggregator.summarize(path :: String.t()) :: {:ok, report} | {:error, reason}

Where `report` is a plain map with exactly these keys:

- `:per_metric`       — a map from metric name string to a stats map containing:
                          `:count`  — integer number of samples
                          `:min`    — number (smallest value seen)
                          `:max`    — number (largest value seen)
                          `:sum`    — number (sum of all values)
                          `:mean`   — float (sum / count)
                         Only metrics actually seen in the file appear.
- `:total_samples`    — integer count of all valid lines processed
- `:time_range`       — a `{first_dt, last_dt}` tuple of `DateTime` structs
                         (the earliest and latest timestamps across all valid
                         lines); `nil` if no valid lines
- `:samples_per_hour` — a map from a `{date_tuple, hour}` tuple
                         (e.g. `{{2024,1,15}, 14}`) to integer count of
                         valid samples in that UTC hour bucket; only hours
                         with at least one sample appear
- `:unique_tags`      — a map from tag key string to a `MapSet` of all
                         distinct tag values seen for that key across
                         all valid lines
- `:malformed_count`  — integer count of lines that could not be parsed as
                         valid JSON or were missing/invalid required fields

Lines that are blank or contain only whitespace should be skipped silently
(they don't count as malformed).

Error handling rules:
- If the file does not exist or cannot be opened, return `{:error, reason}`.
- Every other failure (bad JSON, missing fields, wrong types) is counted in
  `:malformed_count`; the line is skipped and processing continues.
- A line is considered malformed if ANY of these is true:
  - It is not valid JSON
  - The top-level JSON value is not an object
  - Any of `"timestamp"`, `"name"`, `"value"`, or `"tags"` is absent
  - `"timestamp"` cannot be parsed as an ISO 8601 datetime
  - `"name"` is not a non-empty string
  - `"value"` is not a number (integer or float)
  - `"tags"` is not a JSON object

Use `Jason` for JSON parsing and the standard `DateTime` module for timestamp
parsing. No other external dependencies.

Stream the file line-by-line so the module can handle files larger than memory.

Give me the complete module in a single file.