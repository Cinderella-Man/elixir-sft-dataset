  test "multiple points in the same series are sorted by timestamp", %{db: db} do
    :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 300, 0.3)
    :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 100, 0.1)
    :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 200, 0.2)

    [{_labels, points}] = TSDB.query(db, "cpu", %{"host" => "a"}, {0, 500})
    assert points == [{100, 0.1}, {200, 0.2}, {300, 0.3}]
  end