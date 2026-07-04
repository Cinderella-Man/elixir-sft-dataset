  test "nested map is deep-merged across layers with per-leaf provenance" do
    layers = [
      {:base, %{db: %{host: "localhost", port: 5432, name: "prod"}}},
      {:override, %{db: %{port: 5433}}}
    ]

    result = LayeredConfig.merge(layers)

    assert result.config.db == %{host: "localhost", port: 5433, name: "prod"}
    assert result.provenance[[:db, :host]] == :base
    assert result.provenance[[:db, :port]] == :override
    assert result.provenance[[:db, :name]] == :base
  end