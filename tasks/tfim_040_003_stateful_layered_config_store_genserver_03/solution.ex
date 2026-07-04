  test "put_layer overrides scalars from the base" do
    s = start(base: %{host: "localhost", port: 4000})

    assert :ok == ConfigStore.put_layer(s, :env, %{port: 9000})

    assert ConfigStore.get_config(s) == %{host: "localhost", port: 9000}
    assert ConfigStore.layers(s) == [:env]
  end