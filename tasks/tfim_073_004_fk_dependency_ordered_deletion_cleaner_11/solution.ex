  test "plain string entries with no dependencies delete in sorted order" do
    DBCleaner.start(:deletion, repo: FakeRepo, tables: ["orders", "carts", "items"])
    DBCleaner.clean()
    assert deleted_tables() == ["carts", "items", "orders"]
  end