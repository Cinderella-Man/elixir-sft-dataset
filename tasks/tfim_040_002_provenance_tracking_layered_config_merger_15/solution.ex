  test "provenance drops paths whose subtree a higher layer replaced with a scalar" do
    layers = [
      {:base, %{db: %{host: "localhost", port: 5432}}},
      {:env, %{db: "disabled"}}
    ]

    result = LayeredConfig.merge(layers)

    assert result.config == %{db: "disabled"}
    assert result.provenance[[:db]] == :env
    refute Map.has_key?(result.provenance, [:db, :host])
    refute Map.has_key?(result.provenance, [:db, :port])
  end