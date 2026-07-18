  test "locking one path does not protect the same key elsewhere" do
    layers = [
      {:base, %{primary: %{token: "real"}, secondary: %{token: "also_real"}}},
      {:env, %{primary: %{token: "fake"}, secondary: %{token: "replaced"}}}
    ]

    result = LayeredConfig.merge(layers, locked: [[:primary, :token]])

    assert result.config.primary.token == "real"
    assert result.config.secondary.token == "replaced"
  end