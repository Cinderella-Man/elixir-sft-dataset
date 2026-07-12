  test "query filters by inclusive time range", %{db: db} do
    for ts <- [100, 200, 300, 400, 500] do
      :ok = ShardedTSDB.insert(db, "m", %{}, ts, ts * 1.0)
    end

    [{_labels, points}] = ShardedTSDB.query(db, "m", %{}, {200, 400})
    assert Enum.map(points, &elem(&1, 0)) == [200, 300, 400]
  end