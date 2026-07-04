  test "release/1 releases the savepoint and any created after it" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    DBCleaner.savepoint("b")
    DBCleaner.savepoint("c")

    assert {:ok, "b"} = DBCleaner.release("b")
    assert DBCleaner.active_savepoints() == ["a"]
    assert Enum.any?(sqls(), &(&1 == "RELEASE SAVEPOINT b"))
  end