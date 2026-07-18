  test "list_strategies path given as a tuple applies to a nested key-path" do
    s =
      start(
        base: %{app: %{plugins: ["core"]}},
        list_strategies: %{{:app, :plugins} => :append}
      )

    ConfigStore.put_layer(s, :env, %{app: %{plugins: ["auth"]}})

    assert ConfigStore.get(s, [:app, :plugins]) == ["core", "auth"]
  end