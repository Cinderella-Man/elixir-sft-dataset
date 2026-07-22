  test "schema groups are processed in first-appearance order, not term order" do
    # Refund appears FIRST in the file while the Order atom sorts first, so a
    # map-iteration implementation is distinguishable from the required one.
    records = [
      %{"type" => "refund", "refund_id" => "r-1", "reason" => "r", "amount" => 1},
      %{"type" => "order", "order_id" => "o-1", "customer" => "A", "amount" => 1}
    ]

    path = tmp_path("group_first_appearance.json")
    write_json!(path, records)

    log =
      ExUnit.CaptureLog.capture_log([level: :info], fn ->
        assert {:ok, _} =
                 MultiSchemaIngestion.ingest(TestRepo, routing(), path,
                   conflict_target: %{Order => [:order_id], Refund => [:refund_id]},
                   batch_size: 10
                 )
      end)

    # The contract's own per-batch info lines carry the schema name: the
    # first-appearing group's line must come first.
    refund_at = :binary.match(log, "Refund") |> elem(0)
    order_at = :binary.match(log, "Order") |> elem(0)
    assert refund_at < order_at
  end