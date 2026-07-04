  test "two lists never count as a type mismatch even in strict mode" do
    base = %{tags: ["a"]}
    override = %{tags: ["b"]}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override, strict: true)
    assert merged.tags == ["b"]
  end