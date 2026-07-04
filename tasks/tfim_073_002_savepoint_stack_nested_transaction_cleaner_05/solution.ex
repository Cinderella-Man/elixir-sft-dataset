  test "rollback_to/1 on an unknown savepoint returns an error" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    assert {:error, {:no_such_savepoint, "z"}} = DBCleaner.rollback_to("z")
  end