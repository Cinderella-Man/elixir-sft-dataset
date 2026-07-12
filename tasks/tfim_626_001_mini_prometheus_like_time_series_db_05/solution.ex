  test "query returns empty list when no data matches", %{db: db} do
    :ok = TSDB.insert(db, "m", %{"a" => "1"}, 100, 1)

    assert [] = TSDB.query(db, "m", %{"a" => "1"}, {500, 600})
    assert [] = TSDB.query(db, "other_metric", %{}, {0, 1000})
  end