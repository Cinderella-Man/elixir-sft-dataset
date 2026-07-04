  test "later layer wins over earlier layer" do
    s = start(base: %{level: :info})
    ConfigStore.put_layer(s, :file, %{level: :warn})
    ConfigStore.put_layer(s, :env, %{level: :error})

    assert ConfigStore.get_config(s).level == :error
    assert ConfigStore.layers(s) == [:file, :env]
  end