  test "truncation: clean/0 includes RESTART IDENTITY CASCADE" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["events"])
    DBCleaner.clean()

    [{:query, sql}] = FakeRepo.calls()
    assert String.contains?(sql, "RESTART IDENTITY")
    assert String.contains?(sql, "CASCADE")
  end