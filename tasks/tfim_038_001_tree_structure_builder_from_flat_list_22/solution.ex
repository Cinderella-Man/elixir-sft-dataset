  test "string ids work the same as integer ids" do
    items = [
      %{id: "root", parent_id: nil},
      %{id: "child", parent_id: "root"}
    ]

    assert {:ok, [root]} = TreeBuilder.build(items)
    assert root.id == "root"
    assert [%{id: "child"}] = root.children
  end