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