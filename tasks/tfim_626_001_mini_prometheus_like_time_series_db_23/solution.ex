  test "inserting integer and float values both work", %{db: db} do
    :ok = TSDB.insert(db, "m", %{}, 100, 42)
    :ok = TSDB.insert(db, "m", %{}, 200, 3.14)

    [{_labels, points}] = TSDB.query(db, "m", %{}, {0, 300})
    assert points == [{100, 42}, {200, 3.14}]
  end