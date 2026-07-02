  test "truncation: clean/0 truncates all listed tables" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users", "posts"])
    DBCleaner.clean()

    calls = FakeRepo.calls()
    assert length(calls) == 2

    sqls = Enum.map(calls, fn {:query, sql} -> sql end)
    assert Enum.any?(sqls, &String.contains?(&1, "users"))
    assert Enum.any?(sqls, &String.contains?(&1, "posts"))
    assert Enum.all?(sqls, &String.contains?(&1, "TRUNCATE"))
  end