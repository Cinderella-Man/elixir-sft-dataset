  test "points exactly on chunk boundaries go into the correct chunk", %{db: db} do
    # chunk_duration_ms = 1_000
    # t=1000 should go into chunk_start=1000, not chunk_start=0
    :ok = TSDB.insert(db, "m", %{}, 999, 1)
    :ok = TSDB.insert(db, "m", %{}, 1000, 2)
    :ok = TSDB.insert(db, "m", %{}, 1001, 3)

    # Query only chunk [1000, 2000)
    [{_labels, points}] = TSDB.query(db, "m", %{}, {1000, 1999})
    assert points == [{1000, 2}, {1001, 3}]
  end