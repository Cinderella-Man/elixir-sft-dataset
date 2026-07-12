  test "querying a sub-range only returns points from relevant chunks", %{db: db} do
    :ok = TSDB.insert(db, "m", %{}, 500, 1)
    :ok = TSDB.insert(db, "m", %{}, 1500, 2)
    :ok = TSDB.insert(db, "m", %{}, 2500, 3)

    [{_labels, points}] = TSDB.query(db, "m", %{}, {1000, 2000})
    assert points == [{1500, 2}]
  end