  test "empty label matcher matches all series for that metric", %{db: db} do
    :ok = RollupTSDB.insert(db, "http", %{"method" => "GET"}, 100, 1)
    :ok = RollupTSDB.insert(db, "http", %{"method" => "POST"}, 100, 2)

    assert length(RollupTSDB.query(db, "http", %{}, {0, 900})) == 2
  end