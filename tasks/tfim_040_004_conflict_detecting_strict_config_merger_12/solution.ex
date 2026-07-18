  test "missing required key is a conflict" do
    base = %{a: 1}
    override = %{}

    assert {:error, [conflict]} = StrictConfigMerger.merge(base, override, required: [[:b]])
    assert conflict.type == :missing_required
    assert conflict.path == [:b]
  end