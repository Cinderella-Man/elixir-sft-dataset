  test "nested map is deep-merged, not replaced wholesale" do
    base = %{db: %{host: "localhost", port: 5432, name: "prod"}}
    override = %{db: %{port: 5433}}

    result = ConfigMerger.merge(base, override)

    assert result.db.host == "localhost"
    assert result.db.port == 5433
    assert result.db.name == "prod"
  end