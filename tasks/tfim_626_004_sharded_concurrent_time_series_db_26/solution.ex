  test "query_agg treats the end of the range as exclusive", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 500, 5)
    :ok = ShardedTSDB.insert(db, "m", %{}, 1000, 10)

    [{_labels, agg}] = ShardedTSDB.query_agg(db, "m", %{}, {0, 1000}, :sum, 1_000)
    assert agg == [{0, 5}]
  end