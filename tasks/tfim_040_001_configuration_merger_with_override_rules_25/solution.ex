  test "locked top-level key does not protect the same key nested deeper" do
    base = %{token: "root_token", db: %{token: "nested_token"}}
    override = %{token: "new_root", db: %{token: "new_nested"}}

    result = ConfigMerger.merge(base, override, locked: [[:token]])

    assert result.token == "root_token"
    assert result.db.token == "new_nested"
  end