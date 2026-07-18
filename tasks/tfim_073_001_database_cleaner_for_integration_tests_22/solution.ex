  test "truncation: a second clean/0 after cleanup issues no further TRUNCATE statements" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users"])
    assert DBCleaner.clean() == :ok
    FakeRepo.reset()

    assert DBCleaner.clean() == :ok
    assert FakeRepo.calls() == []
  end