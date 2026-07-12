  test "query merges points spanning multiple chunks sorted by timestamp", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 1500, 2)
    :ok = ShardedTSDB.insert(db, "m", %{}, 500, 1)
    :ok = ShardedTSDB.insert(db, "m", %{}, 900, 3)
    :ok = ShardedTSDB.insert(db, "m", %{}, 2400, 4)

    [{_labels, points}] = ShardedTSDB.query(db, "m", %{}, {0, 5000})
    assert points == [{500, 1}, {900, 3}, {1500, 2}, {2400, 4}]
  end