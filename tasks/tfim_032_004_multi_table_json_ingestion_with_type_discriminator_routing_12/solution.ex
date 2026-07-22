  test "inserts each schema group in the order records appeared in the file" do
    import Ecto.Query, only: [from: 2]

    # Types are interleaved so a group that preserves file order is
    # distinguishable from one that reverses or shuffles it, and batch_size
    # forces each group to span multiple insert_all calls.
    records = [
      %{"type" => "order", "order_id" => "o-a", "customer" => "A", "amount" => 1},
      %{"type" => "refund", "refund_id" => "r-a", "reason" => "ra", "amount" => 10},
      %{"type" => "order", "order_id" => "o-b", "customer" => "B", "amount" => 2},
      %{"type" => "order", "order_id" => "o-c", "customer" => "C", "amount" => 3},
      %{"type" => "refund", "refund_id" => "r-b", "reason" => "rb", "amount" => 20},
      %{"type" => "order", "order_id" => "o-d", "customer" => "D", "amount" => 4},
      %{"type" => "refund", "refund_id" => "r-c", "reason" => "rc", "amount" => 30}
    ]

    path = tmp_path("group_order.json")
    write_json!(path, records)

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path,
               conflict_target: %{Order => [:order_id], Refund => [:refund_id]},
               batch_size: 2
             )

    assert stats.by_schema[Order].inserted == 4
    assert stats.by_schema[Refund].inserted == 3

    # Autoincrement ids increase with insertion order, so ordering rows by id
    # replays the sequence in which each group was written.
    order_ids = TestRepo.all(from(o in Order, order_by: [asc: o.id], select: o.order_id))
    refund_ids = TestRepo.all(from(r in Refund, order_by: [asc: r.id], select: r.refund_id))

    assert order_ids == ["o-a", "o-b", "o-c", "o-d"]
    assert refund_ids == ["r-a", "r-b", "r-c"]
  end