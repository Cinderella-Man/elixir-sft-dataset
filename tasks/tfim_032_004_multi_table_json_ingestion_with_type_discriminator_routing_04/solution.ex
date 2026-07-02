  test "counts records with no type field as missing_type" do
    records = [
      %{"type" => "order", "order_id" => "o-1", "customer" => "Alice", "amount" => 100},
      %{"order_id" => "o-2", "customer" => "Bob", "amount" => 200},
      %{"foo" => "bar"}
    ]

    path = tmp_path("missing_type.json")
    write_json!(path, records)

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]}
             )

    assert stats.total == 3
    assert stats.missing_type == 2
    assert stats.unroutable == 0
    assert stats.by_schema[Order].inserted == 1
  end