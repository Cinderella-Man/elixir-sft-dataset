  test "savepoint/1 issues SAVEPOINT and tracks the stack" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    assert {:ok, "a"} = DBCleaner.savepoint("a")
    assert {:ok, "b"} = DBCleaner.savepoint("b")

    assert DBCleaner.active_savepoints() == ["a", "b"]
    assert Enum.any?(sqls(), &(&1 == "SAVEPOINT a"))
    assert Enum.any?(sqls(), &(&1 == "SAVEPOINT b"))
  end