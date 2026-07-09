  test "routes records to correct schemas based on type field" do
    records = [
      %{"type" => "order", "order_id" => "o-1", "customer" => "Alice", "amount" => 100},
      %{"type" => "refund", "refund_id" => "r-1", "reason" => "damaged", "amount" => 50},
      %{"type" => "order", "order_id" => "o-2", "customer" => "Bob", "amount" => 200},
      %{"type" => "order", "order_id" => "o-3", "customer" => "Carol", "amount" => 300},
      %{"type" => "refund", "refund_id" => "r-2", "reason" => "wrong item", "amount" => 75}
    ]

    path = tmp_path("mixed_types.json")
    write_json!(path, records)

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]},
               batch_size: 2
             )

    assert stats.total == 5
    assert stats.unroutable == 0
    assert stats.missing_type == 0

    assert stats.by_schema[Order].inserted == 3
    assert stats.by_schema[Order].failed == 0
    assert stats.by_schema[Refund].inserted == 2
    assert stats.by_schema[Refund].failed == 0

    assert length(all_orders()) == 3
    assert length(all_refunds()) == 2
  end