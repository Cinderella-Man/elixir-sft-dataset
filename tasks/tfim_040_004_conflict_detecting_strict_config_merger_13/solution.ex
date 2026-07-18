  test "present required key passes" do
    base = %{a: %{b: 1}}
    override = %{}

    assert {:ok, _merged} = StrictConfigMerger.merge(base, override, required: [[:a, :b]])
  end