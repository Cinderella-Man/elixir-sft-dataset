  test "per-key list strategy overrides the global strategy" do
    s =
      start(
        base: %{tags: ["a"], plugins: ["core"]},
        list_strategy: :replace,
        list_strategies: %{[:tags] => :append}
      )

    ConfigStore.put_layer(s, :env, %{tags: ["b"], plugins: ["extra"]})

    cfg = ConfigStore.get_config(s)
    assert cfg.tags == ["a", "b"]
    assert cfg.plugins == ["extra"]
  end