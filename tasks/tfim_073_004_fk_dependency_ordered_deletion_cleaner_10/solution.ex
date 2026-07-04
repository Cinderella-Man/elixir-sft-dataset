  test "start/2 raises on an invalid table identifier" do
    assert_raise ArgumentError, fn ->
      DBCleaner.start(:deletion, repo: FakeRepo, tables: ["users; DROP TABLE x"])
    end
  end