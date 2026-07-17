Implement the private `compute_top_accounts/1` function. It receives the
accumulator's `volume_by_account` map — a map from `account_id` string to the
total amount summed across all of that account's transactions (regardless of
credit/debit). It must return a list of at most 5 `{account_id, total_volume}`
tuples sorted in descending order by `total_volume`, breaking ties by ordering
`account_id` alphabetically (ascending). Each returned `total_volume` must be a
float. If there are 5 or fewer accounts, return them all (still sorted); if the
input is empty, return an empty list.

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
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      _ -> :error
    end
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
    # TODO
  end
end
```