  test "unknown metric returns empty list", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{}, 100, 1)
    assert [] = RollupTSDB.query(db, "other", %{}, {0, 10_000})
  end