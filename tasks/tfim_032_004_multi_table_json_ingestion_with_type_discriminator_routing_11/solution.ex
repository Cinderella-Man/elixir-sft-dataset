  test "continues processing other schemas after a batch failure" do
    good_orders =
      Enum.map(1..5, fn i ->
        %{"type" => "order", "order_id" => "o-#{i}", "customer" => "c #{i}", "amount" => i}
      end)

    # Refunds missing the required "reason" field — NOT NULL will fail
    bad_refunds =
      Enum.map(1..3, fn i ->
        %{"type" => "refund", "refund_id" => "bad-#{i}", "amount" => i}
      end)

    good_refunds =
      Enum.map(1..2, fn i ->
        %{"type" => "refund", "refund_id" => "good-#{i}", "reason" => "ok #{i}", "amount" => i}
      end)

    records = good_orders ++ bad_refunds ++ good_refunds
    path = tmp_path("partial_multi.json")
    write_json!(path, records)

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]},
               batch_size: 3
             )

    assert stats.total == 10

    # Orders should all succeed
    assert stats.by_schema[Order].inserted == 5
    assert stats.by_schema[Order].failed == 0

    # Refunds: batch of bad_refunds (3) should fail, batch of good_refunds (2) should succeed
    assert stats.by_schema[Refund].failed == 3
    assert stats.by_schema[Refund].inserted == 2

    assert length(all_orders()) == 5
    assert length(all_refunds()) == 2
  end