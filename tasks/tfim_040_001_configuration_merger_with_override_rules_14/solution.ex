  test "locked top-level key is not overridden" do
    base = %{secret: "base_secret", other: "base"}
    override = %{secret: "hacked!", other: "overridden"}

    result = ConfigMerger.merge(base, override, locked: [[:secret]])

    assert result.secret == "base_secret"
    assert result.other == "overridden"
  end