  test "nested maps are deep-merged across base and layers" do
    s = start(base: %{db: %{host: "localhost", port: 5432, name: "prod"}})
    ConfigStore.put_layer(s, :override, %{db: %{port: 5433}})

    assert ConfigStore.get_config(s).db == %{host: "localhost", port: 5433, name: "prod"}
  end