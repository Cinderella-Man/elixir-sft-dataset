  test "series with no buckets in range is omitted", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{"a" => "1"}, 100, 1)
    assert [] = RollupTSDB.query(db, "m", %{"a" => "1"}, {5000, 6000})
  end