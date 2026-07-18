  test "promoted orphans keep their input position among real roots" do
    items = [
      %{id: :a, parent_id: nil},
      %{id: :orphan, parent_id: :missing},
      %{id: :b, parent_id: nil},
      %{id: :kid, parent_id: :orphan}
    ]

    assert {:ok, nodes} = TreePaths.build(items, orphan_strategy: :raise_to_root)
    assert ids(nodes) == [:a, :orphan, :kid, :b]

    [_a, orphan, kid, _b] = nodes
    assert orphan.depth == 0 and orphan.path == [:orphan]
    assert kid.depth == 1 and kid.path == [:orphan, :kid]
  end