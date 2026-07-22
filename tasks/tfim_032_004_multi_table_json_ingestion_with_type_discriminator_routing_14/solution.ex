  test "a non-string type discriminator value is counted unroutable, never raises" do
    records = [
      %{"type" => %{"weird" => 1}, "order_id" => "o-x"},
      %{"type" => [1, 2], "order_id" => "o-y"},
      %{"type" => "order", "order_id" => "o-1", "customer" => "A", "amount" => 1}
    ]

    path = tmp_path("nonstring_type.json")
    write_json!(path, records)

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]}
             )

    assert stats.total == 3
    assert stats.unroutable == 2
    assert stats.by_schema[Order].inserted == 1
  end