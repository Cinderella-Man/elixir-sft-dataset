  test "counts records with unknown type as unroutable" do
    records = [
      %{"type" => "order",   "order_id" => "o-1", "customer" => "Alice", "amount" => 100},
      %{"type" => "unknown", "foo" => "bar"},
      %{"type" => "refund",  "refund_id" => "r-1", "reason" => "oops", "amount" => 25},
      %{"type" => "mystery", "baz" => "qux"}
    ]

    path = tmp_path("unroutable.json")
    write_json!(path, records)

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]}
             )

    assert stats.total == 4
    assert stats.unroutable == 2
    assert stats.missing_type == 0
    assert stats.by_schema[Order].inserted == 1
    assert stats.by_schema[Refund].inserted == 1
  end