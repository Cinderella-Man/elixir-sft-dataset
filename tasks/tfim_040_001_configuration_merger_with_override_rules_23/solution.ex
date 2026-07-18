  test "per-key :replace takes precedence over global :append strategy" do
    base = %{tags: ["a", "b"], plugins: ["core"]}
    override = %{tags: ["c"], plugins: ["extra"]}

    result =
      ConfigMerger.merge(base, override,
        list_strategy: :append,
        list_strategies: %{[:tags] => :replace}
      )

    assert result.tags == ["c"]
    assert result.plugins == ["core", "extra"]
  end