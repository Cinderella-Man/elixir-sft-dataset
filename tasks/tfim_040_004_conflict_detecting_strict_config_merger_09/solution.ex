  test "locked violation is a conflict regardless of strict" do
    base = %{secret: "keep"}
    override = %{secret: "change"}

    assert {:error, [conflict]} = StrictConfigMerger.merge(base, override, locked: [[:secret]])
    assert conflict.type == :locked_violation
    assert conflict.path == [:secret]
    assert conflict.base == "keep"
    assert conflict.override == "change"
  end