  test "explicit :replace strategy replaces lists" do
    base = %{tags: [1, 2, 3]}
    override = %{tags: [4, 5]}

    result = ConfigMerger.merge(base, override, list_strategy: :replace)

    assert result.tags == [4, 5]
  end