  test "a failed batch still gets its Logger.info running-totals line" do
    # Refunds missing the NOT NULL "reason" fail their batch; the good batch
    # after it succeeds. "After every batch" is unconditional, so TWO refund
    # info lines must appear — the error log does not replace the first.
    records =
      Enum.map(1..3, fn i ->
        %{"type" => "refund", "refund_id" => "bad-#{i}", "amount" => i}
      end) ++
        Enum.map(1..2, fn i ->
          %{"type" => "refund", "refund_id" => "good-#{i}", "reason" => "ok", "amount" => i}
        end)

    path = tmp_path("failed_batch_info.json")
    write_json!(path, records)

    log =
      ExUnit.CaptureLog.capture_log([level: :info], fn ->
        assert {:ok, stats} =
                 MultiSchemaIngestion.ingest(TestRepo, routing(), path,
                   conflict_target: %{Order => [:order_id], Refund => [:refund_id]},
                   batch_size: 3
                 )

        assert stats.by_schema[Refund].failed == 3
        assert stats.by_schema[Refund].inserted == 2
      end)

    info_lines =
      log
      |> String.split("\n")
      |> Enum.filter(&(&1 =~ "[info]" and &1 =~ "Refund"))

    assert length(info_lines) == 2
  end