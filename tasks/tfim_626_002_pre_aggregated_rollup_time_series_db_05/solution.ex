  test "on a tie for the largest timestamp, the latest-arriving point wins for last", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{}, 500, 1)
    :ok = RollupTSDB.insert(db, "m", %{}, 500, 2)

    [{_labels, [{0, stats}]}] = RollupTSDB.query(db, "m", %{}, {0, 900})
    assert stats.last == 2
    assert stats.first == 1
  end