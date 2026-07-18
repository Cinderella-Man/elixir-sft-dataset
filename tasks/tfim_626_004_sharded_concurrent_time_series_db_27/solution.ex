  test "query_agg on an unknown metric returns an empty list", %{db: db} do
    assert [] = ShardedTSDB.query_agg(db, "nope", %{}, {0, 1000}, :sum, 1_000)
  end