  test "query filters by time range (inclusive bounds)", %{db: db} do
    for ts <- [100, 200, 300, 400, 500] do
      :ok = TSDB.insert(db, "m", %{}, ts, ts * 1.0)
    end

    [{_labels, points}] = TSDB.query(db, "m", %{}, {200, 400})
    timestamps = Enum.map(points, &elem(&1, 0))
    assert timestamps == [200, 300, 400]
  end