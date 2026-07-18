  test "integer and float values both accumulate", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{}, 100, 42)
    :ok = RollupTSDB.insert(db, "m", %{}, 200, 3.0)

    [{_labels, [{0, stats}]}] = RollupTSDB.query(db, "m", %{}, {0, 900})
    assert stats.count == 2
    assert_in_delta stats.sum, 45.0, 0.0001
  end