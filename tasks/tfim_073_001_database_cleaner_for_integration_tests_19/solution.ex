  test "truncation: clean/0 emits the exact bare-identifier TRUNCATE statement per table" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users", "posts"])
    DBCleaner.clean()

    assert FakeRepo.calls() == [
             {:query, "TRUNCATE users RESTART IDENTITY CASCADE"},
             {:query, "TRUNCATE posts RESTART IDENTITY CASCADE"}
           ]
  end