  test "empty label matcher matches all series for that metric", %{db: db} do
    :ok = TSDB.insert(db, "http", %{"method" => "GET"}, 100, 1)
    :ok = TSDB.insert(db, "http", %{"method" => "POST"}, 100, 2)

    result = TSDB.query(db, "http", %{}, {0, 200})
    assert length(result) == 2
  end