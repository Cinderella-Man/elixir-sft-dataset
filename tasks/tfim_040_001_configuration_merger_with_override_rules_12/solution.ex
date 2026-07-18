  test "per-key list strategy overrides global strategy" do
    base = %{
      tags: ["a", "b"],
      plugins: ["core"]
    }

    override = %{
      tags: ["c"],
      plugins: ["extra"]
    }

    result =
      ConfigMerger.merge(base, override,
        list_strategy: :replace,
        list_strategies: %{[:tags] => :append}
      )

    # :tags uses per-key :append
    assert result.tags == ["a", "b", "c"]
    # :plugins uses global :replace
    assert result.plugins == ["extra"]
  end