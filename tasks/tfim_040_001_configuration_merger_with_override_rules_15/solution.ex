  test "locked nested key is not overridden" do
    base = %{db: %{password: "s3cr3t", host: "localhost"}}
    override = %{db: %{password: "pwned", host: "evil.host"}}

    result = ConfigMerger.merge(base, override, locked: [[:db, :password]])

    assert result.db.password == "s3cr3t"
    assert result.db.host == "evil.host"
  end