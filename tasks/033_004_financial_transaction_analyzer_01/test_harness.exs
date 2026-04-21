defmodule TransactionAnalyzerTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp tmp_path(name) do
    dir = System.tmp_dir!()
    Path.join(dir, "txn_test_#{name}_#{System.unique_integer([:positive])}.jsonl")
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
    assert r.transaction_count == %{"credit" => 4, "debit" => 3}
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
end
