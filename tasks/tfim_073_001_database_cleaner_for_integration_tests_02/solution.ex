  test "truncation: start/2 is a no-op" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users", "posts"])
    assert FakeRepo.calls() == []
  end