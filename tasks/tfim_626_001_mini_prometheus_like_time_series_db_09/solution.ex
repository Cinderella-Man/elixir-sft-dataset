  test "data points span multiple chunks correctly", %{db: db} do
    # chunk_duration_ms = 1_000, so chunk boundaries at 0, 1000, 2000 ...
    :ok = TSDB.insert(db, "m", %{}, 500, 1)
    :ok = TSDB.insert(db, "m", %{}, 1500, 2)
    :ok = TSDB.insert(db, "m", %{}, 2500, 3)

    [{_labels, points}] = TSDB.query(db, "m", %{}, {0, 3000})
    assert points == [{500, 1}, {1500, 2}, {2500, 3}]
  end