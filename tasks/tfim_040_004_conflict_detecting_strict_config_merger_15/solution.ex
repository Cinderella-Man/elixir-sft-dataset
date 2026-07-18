  test "multiple conflicts are returned sorted by path" do
    base = %{a: 1, z: 2}
    override = %{a: "x", z: [1]}

    assert {:error, conflicts} = StrictConfigMerger.merge(base, override, strict: true)
    assert Enum.map(conflicts, & &1.path) == [[:a], [:z]]
    assert Enum.all?(conflicts, &(&1.type == :type_mismatch))
  end