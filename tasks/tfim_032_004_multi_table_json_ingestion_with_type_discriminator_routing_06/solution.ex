  test "uses per-schema conflict targets from a map" do
    records = [
      %{"type" => "order", "order_id" => "o-1", "customer" => "Alice", "amount" => 100},
      %{"type" => "refund", "refund_id" => "r-1", "reason" => "damaged", "amount" => 50}
    ]

    path = tmp_path("per_schema_conflict.json")
    write_json!(path, records)

    # First insert
    MultiSchemaIngestion.ingest(TestRepo, routing(), path,
      conflict_target: %{Order => [:order_id], Refund => [:refund_id]},
      on_conflict: :nothing
    )

    # Second insert — same IDs, on_conflict: :nothing means no error, no update
    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]},
               on_conflict: :nothing
             )

    assert stats.by_schema[Order].failed == 0
    assert stats.by_schema[Refund].failed == 0

    # Still only 1 of each
    assert length(all_orders()) == 1
    assert length(all_refunds()) == 1
  end