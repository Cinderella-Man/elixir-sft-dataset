Write me an Elixir module called `TransactionAnalyzer` that parses a structured
financial transaction file and produces an analysis report.

Each line of the input file is an independent JSON object with these fields:
- `"timestamp"`  — an ISO 8601 datetime string (e.g. `"2024-01-15T14:03:22Z"`)
- `"account_id"` — a non-empty string identifying the account
- `"type"`       — either `"credit"` or `"debit"` (exactly these two strings)
- `"amount"`     — a positive number (integer or float, must be > 0)
- `"currency"`   — a non-empty string (e.g. `"USD"`, `"EUR"`)

I need one public function:

    TransactionAnalyzer.analyze(path :: String.t()) :: {:ok, report} | {:error, reason}

Where `report` is a plain map with exactly these keys:

- `:balance_by_account`  — a map from account_id string to a float net balance.
                            Credits add to the balance; debits subtract.
                            Only accounts actually seen appear.
- `:volume_by_currency`  — a map from currency string to a float total volume
                            (sum of all amounts regardless of credit/debit).
                            Only currencies actually seen appear.
- `:transaction_count`   — a map from type string (`"credit"` or `"debit"`)
                            to integer count. Only types actually seen appear.
- `:top_accounts`        — a list of at most 5 `{account_id, total_volume}`
                            tuples where total_volume is the sum of all amounts
                            for that account (regardless of type). Sorted
                            descending by total_volume, then alphabetically
                            by account_id to break ties.
- `:daily_volume`        — a map from a date tuple (e.g. `{2024, 1, 15}`)
                            to a float total volume for that UTC day.
                            Only days with at least one transaction appear.
- `:time_range`          — a `{first_dt, last_dt}` tuple of `DateTime` structs;
                            `nil` if no valid lines
- `:malformed_count`     — integer count of lines that could not be parsed

Lines that are blank or contain only whitespace should be skipped silently
(they don't count as malformed).

Error handling rules:
- If the file does not exist or cannot be opened, return `{:error, reason}`.
- Every other failure (bad JSON, missing fields, wrong types, invalid values)
  is counted in `:malformed_count`; the line is skipped and processing continues.
- A line is considered malformed if ANY of these is true:
  - It is not valid JSON
  - The top-level JSON value is not an object
  - Any of `"timestamp"`, `"account_id"`, `"type"`, `"amount"`, or
    `"currency"` is absent
  - `"timestamp"` cannot be parsed as an ISO 8601 datetime
  - `"account_id"` or `"currency"` is not a non-empty string
  - `"type"` is not exactly `"credit"` or `"debit"`
  - `"amount"` is not a positive number (> 0)

Use `Jason` for JSON parsing and the standard `DateTime` module for timestamp
parsing. No other external dependencies.

Stream the file line-by-line so the module can handle files larger than memory.

Give me the complete module in a single file.