  test "base-only config is returned when no layers added" do
    s = start(base: %{a: 1, b: %{c: 2}})

    assert ConfigStore.get_config(s) == %{a: 1, b: %{c: 2}}
    assert ConfigStore.layers(s) == []
  end