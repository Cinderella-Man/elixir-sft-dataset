  test "merging empty base with override returns override" do
    override = %{x: 10, y: %{z: 20}}

    result = ConfigMerger.merge(%{}, override)

    assert result == override
  end