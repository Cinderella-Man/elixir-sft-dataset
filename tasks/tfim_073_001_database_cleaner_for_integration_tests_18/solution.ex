  test "truncation: a raise from query!/3 makes clean/0 return {:error, message}" do
    DBCleaner.start(:truncation, repo: CleanRaisesRepo, tables: ["users"])
    assert {:error, message} = DBCleaner.clean()
    assert is_binary(message)
  end