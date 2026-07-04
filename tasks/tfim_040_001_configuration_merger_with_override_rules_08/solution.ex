  test "lists are replaced by default" do
    base = %{tags: ["a", "b", "c"]}
    override = %{tags: ["x"]}

    result = ConfigMerger.merge(base, override)

    assert result.tags == ["x"]
  end