  test "query omits series with no points in range", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 10)
    assert [] = CounterTSDB.query(db, "reqs", %{"i" => "a"}, {500, 600})
  end