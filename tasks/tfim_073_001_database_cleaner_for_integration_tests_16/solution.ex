  test "truncation: clean/0 returns :ok on success" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users"])
    assert DBCleaner.clean() == :ok
  end