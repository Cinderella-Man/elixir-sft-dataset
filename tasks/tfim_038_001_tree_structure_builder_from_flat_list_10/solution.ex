  test "roots preserve their input order" do
    items = [
      %{id: :c, parent_id: nil},
      %{id: :a, parent_id: nil},
      %{id: :b, parent_id: nil}
    ]

    assert {:ok, roots} = TreeBuilder.build(items)
    assert Enum.map(roots, & &1.id) == [:c, :a, :b]
  end