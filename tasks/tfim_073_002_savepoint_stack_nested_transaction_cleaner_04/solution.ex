  test "rollback_to/1 issues ROLLBACK TO and trims newer savepoints" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    DBCleaner.savepoint("b")
    DBCleaner.savepoint("c")

    assert {:ok, "b"} = DBCleaner.rollback_to("b")
    assert DBCleaner.active_savepoints() == ["a", "b"]
    assert Enum.any?(sqls(), &(&1 == "ROLLBACK TO SAVEPOINT b"))
  end