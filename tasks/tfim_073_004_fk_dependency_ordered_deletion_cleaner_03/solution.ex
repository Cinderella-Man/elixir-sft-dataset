  test "clean/0 deletes children before the parents they reference" do
    DBCleaner.start(:deletion,
      repo: FakeRepo,
      tables: [{"comments", ["posts"]}, {"posts", ["users"]}, "users"]
    )

    assert :ok = DBCleaner.clean()
    assert deleted_tables() == ["comments", "posts", "users"]
  end