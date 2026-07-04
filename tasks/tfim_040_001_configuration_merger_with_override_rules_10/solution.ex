  test ":append strategy concatenates lists" do
    base = %{plugins: ["plug_a", "plug_b"]}
    override = %{plugins: ["plug_c"]}

    result = ConfigMerger.merge(base, override, list_strategy: :append)

    assert result.plugins == ["plug_a", "plug_b", "plug_c"]
  end