  test "raised orphans and real roots together follow original input order" do
    items = [
      %{id: :orphan_a, parent_id: :missing},
      %{id: :root_b, parent_id: nil},
      %{id: :orphan_c, parent_id: :gone},
      %{id: :root_d, parent_id: nil}
    ]

    opts = [orphan_strategy: :raise_to_root]
    assert {:ok, roots} = TreeBuilder.build(items, opts)
    assert Enum.map(roots, & &1.id) == [:orphan_a, :root_b, :orphan_c, :root_d]
  end