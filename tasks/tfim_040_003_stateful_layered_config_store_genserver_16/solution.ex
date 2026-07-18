  test "re-putting a layer replaces its whole map rather than merging with the old map" do
    s = start(base: %{})
    ConfigStore.put_layer(s, :env, %{a: 1, stale: true})
    ConfigStore.put_layer(s, :env, %{a: 2})

    assert ConfigStore.get_config(s) == %{a: 2}
    assert ConfigStore.layers(s) == [:env]
  end