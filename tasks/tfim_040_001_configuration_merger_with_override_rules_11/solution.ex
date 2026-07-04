  test ":append on nested list" do
    base = %{server: %{allowed_ips: ["10.0.0.1"]}}
    override = %{server: %{allowed_ips: ["10.0.0.2", "10.0.0.3"]}}

    result = ConfigMerger.merge(base, override, list_strategy: :append)

    assert result.server.allowed_ips == ["10.0.0.1", "10.0.0.2", "10.0.0.3"]
  end