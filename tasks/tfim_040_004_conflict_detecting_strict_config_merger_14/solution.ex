  test "append list strategy concatenates and returns :ok" do
    base = %{plugins: ["core"]}
    override = %{plugins: ["extra"]}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override, list_strategy: :append)
    assert merged.plugins == ["core", "extra"]
  end