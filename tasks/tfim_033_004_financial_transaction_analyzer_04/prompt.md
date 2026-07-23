# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule TransactionAnalyzerTest do
  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp tmp_path(name) do
    dir = System.tmp_dir!()
    Path.join(dir, "txn_test_#{name}_#{System.pid()}_#{System.unique_integer([:positive])}.jsonl")
  end

  defp write_lines(path, lines) do
    File.write!(path, Enum.join(lines, "\n") <> "\n")
  end

  defp txn_line(timestamp, account_id, type, amount, currency) do
    Jason.encode!(%{
      "timestamp" => timestamp,
      "account_id" => account_id,
      "type" => type,
      "amount" => amount,
      "currency" => currency
    })
  end

  # ---------------------------------------------------------------------------
  # Known-distribution fixture
  #
  # Layout (all times UTC):
  #   2024-01-15T10:00:00Z  acct_1  credit  1000.00  USD
  #   2024-01-15T10:30:00Z  acct_1  debit    250.50  USD
  #   2024-01-15T11:00:00Z  acct_2  credit   500.00  EUR
  #   2024-01-15T11:30:00Z  acct_2  debit    100.00  EUR
  #   2024-01-15T12:00:00Z  acct_1  credit   300.00  USD
  #   2024-01-15T12:30:00Z  acct_3  credit  2000.00  GBP
  #   2024-01-16T09:00:00Z  acct_3  debit    750.00  GBP
  #   <blank line>
  #   <malformed JSON>
  #   <invalid type "transfer">
  # ---------------------------------------------------------------------------

  defp write_fixture(path) do
    lines = [
      txn_line("2024-01-15T10:00:00Z", "acct_1", "credit", 1000.00, "USD"),
      txn_line("2024-01-15T10:30:00Z", "acct_1", "debit", 250.50, "USD"),
      txn_line("2024-01-15T11:00:00Z", "acct_2", "credit", 500.00, "EUR"),
      txn_line("2024-01-15T11:30:00Z", "acct_2", "debit", 100.00, "EUR"),
      txn_line("2024-01-15T12:00:00Z", "acct_1", "credit", 300.00, "USD"),
      txn_line("2024-01-15T12:30:00Z", "acct_3", "credit", 2000.00, "GBP"),
      txn_line("2024-01-16T09:00:00Z", "acct_3", "debit", 750.00, "GBP"),
      "",
      "not json!!!",
      Jason.encode!(%{
        "timestamp" => "2024-01-16T10:00:00Z",
        "account_id" => "acct_1",
        "type" => "transfer",
        "amount" => 100,
        "currency" => "USD"
      })
      # ^^^ invalid type "transfer"
    ]

    write_lines(path, lines)
  end

  # ---------------------------------------------------------------------------
  # Main fixture tests
  # ---------------------------------------------------------------------------

  setup do
    path = tmp_path("fixture")
    write_fixture(path)
    on_exit(fn -> File.rm(path) end)
    {:ok, report} = TransactionAnalyzer.analyze(path)
    %{report: report}
  end

  test "balance_by_account is correct", %{report: r} do
    # acct_1: +1000 - 250.50 + 300 = 1049.50
    # acct_2: +500 - 100 = 400.00
    # acct_3: +2000 - 750 = 1250.00
    assert_in_delta r.balance_by_account["acct_1"], 1049.50, 0.001
    assert_in_delta r.balance_by_account["acct_2"], 400.00, 0.001
    assert_in_delta r.balance_by_account["acct_3"], 1250.00, 0.001
  end

  test "volume_by_currency is correct", %{report: r} do
    # USD: 1000 + 250.50 + 300 = 1550.50
    # EUR: 500 + 100 = 600.00
    # GBP: 2000 + 750 = 2750.00
    assert_in_delta r.volume_by_currency["USD"], 1550.50, 0.001
    assert_in_delta r.volume_by_currency["EUR"], 600.00, 0.001
    assert_in_delta r.volume_by_currency["GBP"], 2750.00, 0.001
  end

  test "transaction_count is correct", %{report: r} do
    # TODO
  end

  test "top_accounts sorted by volume descending then alphabetically", %{report: r} do
    # acct_3: 2000 + 750 = 2750
    # acct_1: 1000 + 250.50 + 300 = 1550.50
    # acct_2: 500 + 100 = 600
    assert length(r.top_accounts) == 3

    [{id1, vol1}, {id2, vol2}, {id3, vol3}] = r.top_accounts
    assert id1 == "acct_3"
    assert_in_delta vol1, 2750.00, 0.001
    assert id2 == "acct_1"
    assert_in_delta vol2, 1550.50, 0.001
    assert id3 == "acct_2"
    assert_in_delta vol3, 600.00, 0.001
  end

  test "top_accounts contains at most 5 entries", %{report: r} do
    assert length(r.top_accounts) <= 5
  end

  test "daily_volume is correct", %{report: r} do
    # 2024-01-15: 1000 + 250.50 + 500 + 100 + 300 + 2000 = 4150.50
    # 2024-01-16: 750
    assert_in_delta r.daily_volume[{2024, 1, 15}], 4150.50, 0.001
    assert_in_delta r.daily_volume[{2024, 1, 16}], 750.00, 0.001
  end

  test "malformed count is correct", %{report: r} do
    # "not json!!!" + invalid type "transfer" = 2
    assert r.malformed_count == 2
  end

  test "time range covers first and last valid timestamps", %{report: r} do
    {:ok, expected_first, _} = DateTime.from_iso8601("2024-01-15T10:00:00Z")
    {:ok, expected_last, _} = DateTime.from_iso8601("2024-01-16T09:00:00Z")

    {first, last} = r.time_range
    assert DateTime.compare(first, expected_first) == :eq
    assert DateTime.compare(last, expected_last) == :eq
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  test "empty file returns zero counts" do
    path = tmp_path("empty")
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert report.balance_by_account == %{}
    assert report.volume_by_currency == %{}
    assert report.transaction_count == %{}
    assert report.top_accounts == []
    assert report.daily_volume == %{}
    assert report.time_range == nil
    assert report.malformed_count == 0
  end

  test "file with only blank lines returns zero counts" do
    path = tmp_path("blanks")
    write_lines(path, ["", "   ", "\t"])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert report.malformed_count == 0
    assert report.time_range == nil
  end

  test "file with only malformed lines" do
    path = tmp_path("all_bad")
    write_lines(path, ["oops", "{}", ~s({"account_id": "x"})])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert report.malformed_count == 3
    assert report.time_range == nil
    assert report.top_accounts == []
  end

  test "nonexistent file returns an error tuple" do
    assert {:error, _reason} = TransactionAnalyzer.analyze("/no/such/file/ever.jsonl")
  end

  test "single valid line produces consistent report" do
    path = tmp_path("single")
    write_lines(path, [txn_line("2024-03-20T08:30:00Z", "acct_x", "credit", 99.99, "USD")])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert_in_delta report.balance_by_account["acct_x"], 99.99, 0.001
    assert report.transaction_count == %{"credit" => 1}
    assert report.malformed_count == 0
    {first, last} = report.time_range
    assert DateTime.compare(first, last) == :eq
  end

  test "zero amount is malformed" do
    path = tmp_path("zero_amt")

    write_lines(path, [
      Jason.encode!(%{
        "timestamp" => "2024-01-01T00:00:00Z",
        "account_id" => "a",
        "type" => "credit",
        "amount" => 0,
        "currency" => "USD"
      })
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert report.malformed_count == 1
  end

  test "negative amount is malformed" do
    path = tmp_path("neg_amt")

    write_lines(path, [
      Jason.encode!(%{
        "timestamp" => "2024-01-01T00:00:00Z",
        "account_id" => "a",
        "type" => "debit",
        "amount" => -50,
        "currency" => "USD"
      })
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert report.malformed_count == 1
  end

  test "empty account_id is malformed" do
    path = tmp_path("empty_acct")

    write_lines(path, [
      Jason.encode!(%{
        "timestamp" => "2024-01-01T00:00:00Z",
        "account_id" => "",
        "type" => "credit",
        "amount" => 100,
        "currency" => "USD"
      })
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert report.malformed_count == 1
  end

  test "top_accounts caps at 5 when more accounts exist" do
    path = tmp_path("top5")

    lines =
      for i <- 1..8 do
        txn_line("2024-06-01T00:00:0#{rem(i, 10)}Z", "acct_#{i}", "credit", i * 100, "USD")
      end

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert length(report.top_accounts) == 5
  end

  test "debit produces negative balance" do
    path = tmp_path("neg_balance")

    write_lines(path, [
      txn_line("2024-01-01T00:00:00Z", "acct_x", "debit", 500.00, "USD")
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert_in_delta report.balance_by_account["acct_x"], -500.00, 0.001
  end

  test "daily_volume spans multiple calendar days" do
    path = tmp_path("multiday")

    lines = [
      txn_line("2024-01-01T23:59:00Z", "a", "credit", 100, "USD"),
      txn_line("2024-01-02T00:01:00Z", "a", "debit", 200, "USD")
    ]

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)

    assert_in_delta report.daily_volume[{2024, 1, 1}], 100.0, 0.001
    assert_in_delta report.daily_volume[{2024, 1, 2}], 200.0, 0.001
  end

  test "top_accounts breaks equal-volume ties alphabetically by account_id" do
    path = tmp_path("ties")

    write_lines(path, [
      txn_line("2024-02-01T00:00:00Z", "acct_b", "credit", 100, "USD"),
      txn_line("2024-02-01T00:00:01Z", "acct_a", "credit", 60, "USD"),
      txn_line("2024-02-01T00:00:02Z", "acct_a", "debit", 40, "USD"),
      txn_line("2024-02-01T00:00:03Z", "acct_c", "credit", 500, "USD")
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert [{"acct_c", _}, {"acct_a", vol_a}, {"acct_b", vol_b}] = report.top_accounts
    assert_in_delta vol_a, 100.0, 0.001
    assert_in_delta vol_b, 100.0, 0.001
  end

  test "path that exists but cannot be opened as a file returns an error tuple" do
    path = tmp_path("is_a_directory")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)

    assert {:error, _reason} = TransactionAnalyzer.analyze(path)
  end

  test "daily_volume buckets an offset timestamp by its UTC day" do
    path = tmp_path("utc_day")

    write_lines(path, [
      txn_line("2024-01-15T23:30:00-05:00", "acct_o", "credit", 100, "USD")
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert Map.keys(report.daily_volume) == [{2024, 1, 16}]
    assert is_float(report.daily_volume[{2024, 1, 16}])
    assert_in_delta report.daily_volume[{2024, 1, 16}], 100.0, 0.001
  end

  test "valid JSON that is not an object counts as malformed" do
    path = tmp_path("non_object")
    write_lines(path, ["123", "[1, 2, 3]", ~s("just a string"), "null", "true"])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert report.malformed_count == 5
    assert report.top_accounts == []
    assert report.time_range == nil
  end

  test "non-empty timestamp string that is not a valid ISO 8601 datetime is malformed" do
    path = tmp_path("bad_ts")

    write_lines(path, [
      txn_line("not-a-date", "acct_t", "credit", 100, "USD"),
      txn_line("2024-13-45", "acct_t", "debit", 50, "USD")
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)

    # Both lines are skipped entirely: nothing is recorded under a fallback date.
    assert report.malformed_count == 2
    assert report.balance_by_account == %{}
    assert report.volume_by_currency == %{}
    assert report.transaction_count == %{}
    assert report.top_accounts == []
    assert report.daily_volume == %{}
    assert report.time_range == nil
  end

  test "integer amounts still produce float balances, currency volumes and top_accounts" do
    path = tmp_path("int_amounts")

    write_lines(path, [
      txn_line("2024-05-01T00:00:00Z", "acct_i", "credit", 100, "USD"),
      txn_line("2024-05-01T01:00:00Z", "acct_i", "debit", 40, "USD"),
      txn_line("2024-05-01T02:00:00Z", "acct_j", "debit", 25, "EUR")
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)

    assert is_float(report.balance_by_account["acct_i"])
    assert is_float(report.balance_by_account["acct_j"])
    assert is_float(report.volume_by_currency["USD"])
    assert is_float(report.volume_by_currency["EUR"])

    assert length(report.top_accounts) == 2

    for {account_id, volume} <- report.top_accounts do
      assert is_binary(account_id)
      assert is_float(volume)
    end

    assert_in_delta report.balance_by_account["acct_i"], 60.0, 0.001
    assert_in_delta report.balance_by_account["acct_j"], -25.0, 0.001
    assert_in_delta report.volume_by_currency["USD"], 140.0, 0.001
    assert_in_delta report.volume_by_currency["EUR"], 25.0, 0.001
  end
end
```
