  test "locked top-level key absent from base is not injected by override" do
    base = %{other: "base"}
    override = %{secret: "injected", other: "overridden"}

    result = ConfigMerger.merge(base, override, locked: [[:secret]])

    refute Map.has_key?(result, :secret)
    assert result.other == "overridden"
  end