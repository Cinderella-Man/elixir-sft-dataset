  test "locked path pointing at a map preserves the entire base subtree" do
    base = %{db: %{host: "localhost", port: 5432}, app: %{name: "MyApp"}}
    override = %{db: %{host: "evil.host", port: 6666, extra: true}, app: %{name: "EvilApp"}}

    result = ConfigMerger.merge(base, override, locked: [[:db]])

    assert result.db == %{host: "localhost", port: 5432}
    assert result.app.name == "EvilApp"
  end