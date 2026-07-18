  test "locked path absent from earlier layers may still be set by a higher layer" do
    layers = [
      {:base, %{db: %{host: "localhost"}}},
      {:env, %{db: %{password: "fresh"}, token: "new"}}
    ]

    result = LayeredConfig.merge(layers, locked: [[:db, :password], [:token]])

    assert result.config.db.password == "fresh"
    assert result.config.token == "new"
    assert result.provenance[[:db, :password]] == :env
    assert result.provenance[[:token]] == :env
  end