  test "truncation: start/2 returns {:ok, :truncation} on success" do
    assert DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users"]) == {:ok, :truncation}
  end