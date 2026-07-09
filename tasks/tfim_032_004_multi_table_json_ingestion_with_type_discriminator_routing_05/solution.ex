  test "supports custom type_field option" do
    records = [
      %{"record_kind" => "order", "order_id" => "o-1", "customer" => "X", "amount" => 10},
      %{"record_kind" => "refund", "refund_id" => "r-1", "reason" => "Y", "amount" => 5}
    ]

    path = tmp_path("custom_type_field.json")
    write_json!(path, records)

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]},
               type_field: "record_kind"
             )

    assert stats.total == 2
    assert stats.by_schema[Order].inserted == 1
    assert stats.by_schema[Refund].inserted == 1
  end