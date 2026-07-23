# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `fetch_nonempty_string` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Design Brief: `TransactionAnalyzer`

## Problem

We need an Elixir module called `TransactionAnalyzer` that parses a structured
financial transaction file and produces an analysis report. The input file must
be processed line by line: each line is an independent JSON object with these
fields:

- `"timestamp"`  — an ISO 8601 datetime string (e.g. `"2024-01-15T14:03:22Z"`)
- `"account_id"` — a non-empty string identifying the account
- `"type"`       — either `"credit"` or `"debit"` (exactly these two strings)
- `"amount"`     — a positive number (integer or float, must be > 0)
- `"currency"`   — a non-empty string (e.g. `"USD"`, `"EUR"`)

## Constraints

- Use `Jason` for JSON parsing and the standard `DateTime` module for timestamp
  parsing. No other external dependencies.
- Stream the file line-by-line so the module can handle files larger than memory.
- Lines that are blank or contain only whitespace should be skipped silently
  (they don't count as malformed).
- Error handling rules:
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
- Deliver the complete module in a single file.

## Required Interface

1. Provide exactly one public function:

       TransactionAnalyzer.analyze(path :: String.t()) :: {:ok, report} | {:error, reason}

2. On success, `report` is a plain map with exactly these keys:

   1. `:balance_by_account`  — a map from account_id string to a float net balance.
      Credits add to the balance; debits subtract. Only accounts actually seen
      appear.
   2. `:volume_by_currency`  — a map from currency string to a float total volume
      (sum of all amounts regardless of credit/debit). Only currencies actually
      seen appear.
   3. `:transaction_count`   — a map from type string (`"credit"` or `"debit"`)
      to integer count. Only types actually seen appear.
   4. `:top_accounts`        — a list of at most 5 `{account_id, total_volume}`
      tuples where total_volume is the sum of all amounts for that account
      (regardless of type). Sorted descending by total_volume, then
      alphabetically by account_id to break ties.
   5. `:daily_volume`        — a map from a date tuple (e.g. `{2024, 1, 15}`)
      to a float total volume for that UTC day. Only days with at least one
      transaction appear.
   6. `:time_range`          — a `{first_dt, last_dt}` tuple of `DateTime`
      structs; `nil` if no valid lines.
   7. `:malformed_count`     — integer count of lines that could not be parsed.

## Acceptance Criteria

- `TransactionAnalyzer.analyze/1` returns `{:ok, report}` or `{:error, reason}`.
- A missing or unopenable file yields `{:error, reason}`.
- Malformed lines (per the rules above) are counted in `:malformed_count`, skipped,
  and do not halt processing; blank/whitespace-only lines are skipped silently and
  are not counted as malformed.
- The returned `report` map contains exactly the seven keys above, each behaving
  as specified — including "only seen" membership for `:balance_by_account`,
  `:volume_by_currency`, `:transaction_count`, and `:daily_volume`; the at-most-5,
  descending-then-alphabetical ordering of `:top_accounts`; and `:time_range` being
  `nil` when there are no valid lines.
- Parsing uses `Jason` and `DateTime` only, with no other external dependencies,
  and the file is streamed line-by-line to handle inputs larger than memory.
- The deliverable is the complete module in a single file.

## The module with `fetch_nonempty_string` missing

```elixir
defmodule TransactionAnalyzer do
  @moduledoc """
  Parses a structured, newline-delimited JSON financial transaction file
  and produces an analysis report.

  Each line must be a JSON object with the fields:
    "timestamp"  – ISO 8601 datetime string
    "account_id" – non-empty string
    "type"       – "credit" or "debit"
    "amount"     – positive number (> 0)
    "currency"   – non-empty string

  Blank / whitespace-only lines are silently skipped.
  Lines that cannot be parsed increment :malformed_count and are otherwise ignored.

  Requires the `jason` dependency in mix.exs:
      {:jason, "~> 1.4"}
  """

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Analyzes the transaction log at `path`. Returns `{:ok, stats}` or `{:error, reason}`."
  @spec analyze(String.t()) :: {:ok, map()} | {:error, term()}
  def analyze(path) do
    case File.open(path, [:read]) do
      {:error, reason} ->
        {:error, reason}

      {:ok, device} ->
        :ok = File.close(device)
        stream_report(path)
    end
  end

  # ---------------------------------------------------------------------------
  # Streaming
  # ---------------------------------------------------------------------------

  defp stream_report(path) do
    report =
      path
      |> File.stream!(:line, [])
      |> Stream.map(&String.trim_trailing(&1, "\n"))
      |> Stream.map(&String.trim_trailing(&1, "\r"))
      |> Enum.reduce(initial_acc(), &process_line/2)
      |> build_report()

    {:ok, report}
  rescue
    error in [File.Error] -> {:error, Map.get(error, :reason, :enoent)}
    error in [IO.StreamError] -> {:error, Map.get(error, :reason, :terminated)}
  end

  # ---------------------------------------------------------------------------
  # Accumulator
  # ---------------------------------------------------------------------------

  defp initial_acc do
    %{
      balance_by_account: %{},
      volume_by_account: %{},
      volume_by_currency: %{},
      transaction_count: %{},
      daily_volume: %{},
      timestamps: nil,
      malformed: 0
    }
  end

  # ---------------------------------------------------------------------------
  # Per-line processing
  # ---------------------------------------------------------------------------

  defp process_line(raw_line, acc) do
    trimmed = String.trim(raw_line)

    if trimmed == "" do
      acc
    else
      case parse_line(trimmed) do
        {:ok, entry} ->
          accumulate(acc, entry)

        :error ->
          %{acc | malformed: acc.malformed + 1}
      end
    end
  end

  defp parse_line(trimmed) do
    with {:ok, obj} when is_map(obj) <- Jason.decode(trimmed),
         {:ok, ts_string} <- fetch_string(obj, "timestamp"),
         {:ok, account_id} <- fetch_nonempty_string(obj, "account_id"),
         {:ok, type} <- fetch_type(obj),
         {:ok, amount} <- fetch_positive_number(obj, "amount"),
         {:ok, currency} <- fetch_nonempty_string(obj, "currency"),
         {:ok, dt} <- parse_timestamp(ts_string) do
      {:ok,
       %{
         timestamp: dt,
         account_id: account_id,
         type: type,
         amount: amount,
         currency: currency
       }}
    else
      _ -> :error
    end
  end

  defp fetch_string(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      _ -> :error
    end
  end

  defp fetch_nonempty_string(map, key) do
    # TODO
  end

  defp fetch_type(map) do
    case Map.fetch(map, "type") do
      {:ok, "credit"} -> {:ok, "credit"}
      {:ok, "debit"} -> {:ok, "debit"}
      _ -> :error
    end
  end

  defp fetch_positive_number(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_number(value) and value > 0 -> {:ok, value}
      _ -> :error
    end
  end

  defp parse_timestamp(ts_string) do
    case DateTime.from_iso8601(ts_string) do
      {:ok, dt, _offset} ->
        {:ok, DateTime.shift_zone!(dt, "Etc/UTC")}

      {:error, _} ->
        :error
    end
  end

  # ---------------------------------------------------------------------------
  # Accumulation
  # ---------------------------------------------------------------------------

  defp accumulate(acc, entry) do
    signed_amount = if entry.type == "credit", do: entry.amount, else: -entry.amount

    acc
    |> update_balance(entry.account_id, signed_amount)
    |> update_volume_by_account(entry.account_id, entry.amount)
    |> update_volume_by_currency(entry.currency, entry.amount)
    |> update_transaction_count(entry.type)
    |> update_daily_volume(entry.timestamp, entry.amount)
    |> update_timestamps(entry.timestamp)
  end

  defp update_balance(acc, account_id, signed_amount) do
    Map.update!(acc, :balance_by_account, fn balances ->
      Map.update(balances, account_id, signed_amount, &(&1 + signed_amount))
    end)
  end

  defp update_volume_by_account(acc, account_id, amount) do
    Map.update!(acc, :volume_by_account, fn volumes ->
      Map.update(volumes, account_id, amount, &(&1 + amount))
    end)
  end

  defp update_volume_by_currency(acc, currency, amount) do
    Map.update!(acc, :volume_by_currency, fn volumes ->
      Map.update(volumes, currency, amount, &(&1 + amount))
    end)
  end

  defp update_transaction_count(acc, type) do
    Map.update!(acc, :transaction_count, fn counts ->
      Map.update(counts, type, 1, &(&1 + 1))
    end)
  end

  defp update_daily_volume(acc, dt, amount) do
    day = day_bucket(dt)

    Map.update!(acc, :daily_volume, fn dv ->
      Map.update(dv, day, amount, &(&1 + amount))
    end)
  end

  defp update_timestamps(acc, dt) do
    Map.update!(acc, :timestamps, fn
      nil ->
        {dt, dt}

      {min_dt, max_dt} ->
        new_min = if DateTime.compare(dt, min_dt) == :lt, do: dt, else: min_dt
        new_max = if DateTime.compare(dt, max_dt) == :gt, do: dt, else: max_dt
        {new_min, new_max}
    end)
  end

  defp day_bucket(%DateTime{year: y, month: m, day: d}) do
    {y, m, d}
  end

  # ---------------------------------------------------------------------------
  # Report construction
  # ---------------------------------------------------------------------------

  defp build_report(acc) do
    %{
      balance_by_account: ensure_float_values(acc.balance_by_account),
      volume_by_currency: ensure_float_values(acc.volume_by_currency),
      transaction_count: acc.transaction_count,
      top_accounts: compute_top_accounts(acc.volume_by_account),
      daily_volume: ensure_float_values(acc.daily_volume),
      time_range: acc.timestamps,
      malformed_count: acc.malformed
    }
  end

  defp ensure_float_values(map) do
    Map.new(map, fn {k, v} -> {k, v / 1} end)
  end

  defp compute_top_accounts(volume_by_account) do
    volume_by_account
    |> Enum.sort(fn {id_a, vol_a}, {id_b, vol_b} ->
      cond do
        vol_a != vol_b -> vol_a > vol_b
        true -> id_a <= id_b
      end
    end)
    |> Enum.take(5)
    |> Enum.map(fn {id, vol} -> {id, vol / 1} end)
  end
end
```

Give me only the complete implementation of `fetch_nonempty_string` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
