  test "first is the value at the smallest timestamp, last at the largest", %{db: db} do
    # Insert out of order; first should track the earliest timestamp (100),
    # last should track the latest timestamp (300).
    :ok = RollupTSDB.insert(db, "m", %{}, 300, 30)
    :ok = RollupTSDB.insert(db, "m", %{}, 100, 10)
    :ok = RollupTSDB.insert(db, "m", %{}, 200, 20)

    [{_labels, [{0, stats}]}] = RollupTSDB.query(db, "m", %{}, {0, 900})
    assert stats.first == 10
    assert stats.last == 30
  end