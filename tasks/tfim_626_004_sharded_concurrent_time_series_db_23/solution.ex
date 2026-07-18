  test "query_agg :avg produces a mean per window across windows", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 10)
    :ok = ShardedTSDB.insert(db, "m", %{}, 200, 20)
    :ok = ShardedTSDB.insert(db, "m", %{}, 1100, 40)

    [{_labels, agg}] = ShardedTSDB.query_agg(db, "m", %{}, {0, 2000}, :avg, 1_000)
    assert agg == [{0, 15.0}, {1000, 40.0}]
  end