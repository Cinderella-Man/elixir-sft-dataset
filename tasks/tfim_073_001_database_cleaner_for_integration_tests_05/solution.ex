  test "truncation: empty tables list results in no queries" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: [])
    DBCleaner.clean()
    assert FakeRepo.calls() == []
  end