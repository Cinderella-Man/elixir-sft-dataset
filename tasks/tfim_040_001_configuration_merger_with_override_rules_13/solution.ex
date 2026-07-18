  test "per-key strategy on deeply nested list" do
    base = %{app: %{server: %{hosts: ["h1"]}}}
    override = %{app: %{server: %{hosts: ["h2"]}}}

    result =
      ConfigMerger.merge(base, override, list_strategies: %{[:app, :server, :hosts] => :append})

    assert result.app.server.hosts == ["h1", "h2"]
  end