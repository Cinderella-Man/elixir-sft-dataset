  test "locked path with identical override value is fine" do
    base = %{secret: "keep", other: 1}
    override = %{secret: "keep", other: 2}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override, locked: [[:secret]])
    assert merged.secret == "keep"
    assert merged.other == 2
  end