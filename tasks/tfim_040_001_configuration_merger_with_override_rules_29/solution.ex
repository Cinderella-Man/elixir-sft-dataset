  test "locked key absent from base is not injected even when override value is a map" do
    base = %{db: %{host: "localhost"}}
    override = %{db: %{host: "evil.host", credentials: %{user: "root", password: "pwned"}}}

    result = ConfigMerger.merge(base, override, locked: [[:db, :credentials]])

    refute Map.has_key?(result.db, :credentials)
    assert result.db.host == "evil.host"
  end