  test "clean/0 with a cyclic spec issues no queries and returns an error" do
    DBCleaner.start(:deletion,
      repo: FakeRepo,
      tables: [{"a", ["b"]}, {"b", ["a"]}]
    )

    assert {:error, {:cycle, ["a", "b"]}} = DBCleaner.clean()
    assert deleted_tables() == []
  end