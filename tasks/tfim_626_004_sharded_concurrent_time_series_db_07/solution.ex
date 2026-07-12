  test "query omits series with no point in range and unknown metric", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{"a" => "1"}, 100, 1)
    assert [] = ShardedTSDB.query(db, "m", %{"a" => "1"}, {500, 600})
    assert [] = ShardedTSDB.query(db, "other", %{}, {0, 1000})
  end