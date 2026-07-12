  test "insert returns :ok", %{db: db} do
    assert :ok = RollupTSDB.insert(db, "cpu", %{"host" => "a"}, 100, 0.5)
  end