  test "a non-object array element is counted missing_type, never raises" do
    path = tmp_path("nonobject_records.json")

    File.write!(
      path,
      Jason.encode!([
        "just a string",
        42,
        %{"type" => "order", "order_id" => "o-1", "customer" => "A", "amount" => 1}
      ])
    )

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]}
             )

    assert stats.total == 3
    assert stats.missing_type == 2
    assert stats.by_schema[Order].inserted == 1
  end