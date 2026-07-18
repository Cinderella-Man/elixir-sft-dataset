  test "cleanup removes expired chunks across shards", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 1)
    :ok = ShardedTSDB.insert(db, "m", %{}, 5000, 2)

    Clock.set(12_000)
    assert :ok = ShardedTSDB.cleanup(db)

    [{_labels, points}] = ShardedTSDB.query(db, "m", %{}, {0, 20_000})
    assert points == [{5000, 2}]
  end