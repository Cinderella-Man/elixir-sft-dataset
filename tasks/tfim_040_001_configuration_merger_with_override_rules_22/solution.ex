  test "locked path is not injectable by override when base lacks the key" do
    base = %{db: %{host: "localhost"}}
    override = %{db: %{host: "evil.host", password: "pwned"}}

    result = ConfigMerger.merge(base, override, locked: [[:db, :password]])

    assert result.db.host == "evil.host"
    refute Map.has_key?(result.db, :password)
  end