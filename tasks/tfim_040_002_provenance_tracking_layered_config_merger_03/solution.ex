  test "later layer overrides scalar and records provenance" do
    layers = [{:base, %{host: "localhost", port: 4000}}, {:env, %{port: 9000}}]

    result = LayeredConfig.merge(layers)

    assert result.config == %{host: "localhost", port: 9000}
    assert result.provenance[[:host]] == :base
    assert result.provenance[[:port]] == :env
  end