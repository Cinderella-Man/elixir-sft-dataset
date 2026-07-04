  test "drop_layer removes a layer" do
    s = start(base: %{v: 0})
    ConfigStore.put_layer(s, :a, %{v: 1})
    ConfigStore.put_layer(s, :b, %{v: 2})

    assert :ok == ConfigStore.drop_layer(s, :b)

    assert ConfigStore.layers(s) == [:a]
    assert ConfigStore.get_config(s).v == 1
  end