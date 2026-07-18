  test "cleanup does not touch chunks that are still within retention", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 1)

    Clock.set(5_000)
    assert :ok = ShardedTSDB.cleanup(db)

    [{_labels, points}] = ShardedTSDB.query(db, "m", %{}, {0, 20_000})
    assert points == [{100, 1}]
    assert ShardedTSDB.series_count(db) == 1
  end