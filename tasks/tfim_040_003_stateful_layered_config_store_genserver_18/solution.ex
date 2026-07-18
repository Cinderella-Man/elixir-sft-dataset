  test "list_strategy defaults to replace when the option is omitted" do
    s = start(base: %{plugins: ["core"]})
    ConfigStore.put_layer(s, :env, %{plugins: ["auth"]})

    assert ConfigStore.get(s, [:plugins]) == ["auth"]
  end