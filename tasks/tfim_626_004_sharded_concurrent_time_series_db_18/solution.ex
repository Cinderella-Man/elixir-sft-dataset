  test "every shard_of index falls within the shard range", %{db: db} do
    for i <- 1..50 do
      idx = ShardedTSDB.shard_of(db, "cpu", %{"host" => "host-#{i}"})
      assert idx in 0..3
    end
  end