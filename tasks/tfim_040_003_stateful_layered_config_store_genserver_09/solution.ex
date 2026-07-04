  test "append list strategy concatenates base and layer lists" do
    s = start(base: %{plugins: ["core"]}, list_strategy: :append)
    ConfigStore.put_layer(s, :a, %{plugins: ["auth"]})
    ConfigStore.put_layer(s, :b, %{plugins: ["metrics"]})

    assert ConfigStore.get_config(s).plugins == ["core", "auth", "metrics"]
  end