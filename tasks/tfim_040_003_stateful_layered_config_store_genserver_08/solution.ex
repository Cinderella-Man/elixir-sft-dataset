  test "get/2 fetches by key-path and returns nil when absent" do
    s = start(base: %{app: %{server: %{port: 80}}})
    ConfigStore.put_layer(s, :env, %{app: %{server: %{port: 443}}})

    assert ConfigStore.get(s, [:app, :server, :port]) == 443
    assert ConfigStore.get(s, [:app, :missing]) == nil
  end