  test "series_count reports distinct series across all shards", %{db: db} do
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 100, 1)
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "b"}, 100, 1)
    :ok = ShardedTSDB.insert(db, "mem", %{"host" => "a"}, 100, 1)
    # Re-inserting into an existing series must not increase the count.
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 200, 2)

    assert ShardedTSDB.series_count(db) == 3
  end