  test "3-level deep merge preserves untouched branches" do
    base = %{
      app: %{
        server: %{host: "0.0.0.0", port: 80, ssl: false},
        cache: %{ttl: 300}
      }
    }

    override = %{
      app: %{
        server: %{port: 443, ssl: true}
      }
    }

    result = ConfigMerger.merge(base, override)

    assert result.app.server.host == "0.0.0.0"
    assert result.app.server.port == 443
    assert result.app.server.ssl == true
    assert result.app.cache.ttl == 300
  end