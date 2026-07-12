  test "points in one series are returned sorted by timestamp", %{db: db} do
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 300, 0.3)
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 100, 0.1)
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 200, 0.2)

    [{_labels, points}] = ShardedTSDB.query(db, "cpu", %{"host" => "a"}, {0, 500})
    assert points == [{100, 0.1}, {200, 0.2}, {300, 0.3}]
  end