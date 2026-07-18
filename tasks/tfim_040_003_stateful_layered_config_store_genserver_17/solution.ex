  test "base defaults to an empty map when the option is omitted" do
    s = start([])

    assert ConfigStore.get_config(s) == %{}

    ConfigStore.put_layer(s, :env, %{a: 1})

    assert ConfigStore.get_config(s) == %{a: 1}
  end