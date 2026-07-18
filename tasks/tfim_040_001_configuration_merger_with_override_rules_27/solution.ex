  test ":append with empty lists on either side yields the other list" do
    result_empty_override =
      ConfigMerger.merge(%{tags: ["a"]}, %{tags: []}, list_strategy: :append)

    result_empty_base = ConfigMerger.merge(%{tags: []}, %{tags: ["b"]}, list_strategy: :append)

    assert result_empty_override.tags == ["a"]
    assert result_empty_base.tags == ["b"]
  end