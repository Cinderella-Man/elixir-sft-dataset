  test "savepoint/1 rejects invalid identifiers without issuing SQL" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    FakeRepo.reset()

    assert {:error, {:invalid_name, "a; DROP TABLE users"}} =
             DBCleaner.savepoint("a; DROP TABLE users")

    assert sqls() == []
  end