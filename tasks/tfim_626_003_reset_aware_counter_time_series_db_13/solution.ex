  test "label matchers select series containing all specified labels", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a", "env" => "prod"}, 0, 0)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a", "env" => "prod"}, 500, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "b", "env" => "dev"}, 0, 0)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "b", "env" => "dev"}, 500, 99)

    result = CounterTSDB.query_range(db, "reqs", %{"env" => "prod"}, {0, 1000}, :increase, 1_000)
    assert [{%{"env" => "prod"}, [{0, 10}]}] = result
  end