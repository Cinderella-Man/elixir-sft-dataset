  test "query_agg correctly buckets across multiple step windows", %{db: db} do
    # step_ms = 500, range [0, 2000)
    # Window [0, 500): t=100 v=1, t=200 v=2
    :ok = TSDB.insert(db, "m", %{}, 100, 1)
    :ok = TSDB.insert(db, "m", %{}, 200, 2)
    # Window [500, 1000): t=600 v=10
    :ok = TSDB.insert(db, "m", %{}, 600, 10)
    # Window [1000, 1500): empty
    # Window [1500, 2000): t=1700 v=99
    :ok = TSDB.insert(db, "m", %{}, 1700, 99)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 2000}, :sum, 500)

    assert agg_points == [{0, 3}, {500, 10}, {1500, 99}]
  end