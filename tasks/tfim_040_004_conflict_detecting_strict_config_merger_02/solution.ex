  test "non-strict merge lets override win and returns :ok" do
    base = %{host: "localhost", port: 4000}
    override = %{port: 9000}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override)
    assert merged == %{host: "localhost", port: 9000}
  end