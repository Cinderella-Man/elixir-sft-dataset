  test "query_agg :sum computes the sum per window", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 10)
    :ok = ShardedTSDB.insert(db, "m", %{}, 200, 20)
    :ok = ShardedTSDB.insert(db, "m", %{}, 300, 30)
    :ok = ShardedTSDB.insert(db, "m", %{}, 1100, 5)
    :ok = ShardedTSDB.insert(db, "m", %{}, 1500, 15)

    [{_labels, agg}] = ShardedTSDB.query_agg(db, "m", %{}, {0, 2000}, :sum, 1_000)
    assert agg == [{0, 60}, {1000, 20}]
  end