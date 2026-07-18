  test "locked nested key is preserved while siblings merge" do
    layers = [
      {:base, %{db: %{password: "keep", host: "localhost"}}},
      {:env, %{db: %{password: "hack", host: "evil.host"}}}
    ]

    result = LayeredConfig.merge(layers, locked: [[:db, :password]])

    assert result.config.db.password == "keep"
    assert result.config.db.host == "evil.host"
    assert result.provenance[[:db, :password]] == :base
    assert result.provenance[[:db, :host]] == :env
  end