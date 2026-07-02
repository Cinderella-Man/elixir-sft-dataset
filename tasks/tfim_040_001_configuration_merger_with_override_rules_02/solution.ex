  test "override replaces scalar at top-level key" do
    base = %{host: "localhost", port: 4000}
    override = %{port: 9000}

    result = ConfigMerger.merge(base, override)

    assert result.host == "localhost"
    assert result.port == 9000
  end