  test "resolves an in-batch parent even when the child appears before the parent" do
    items = [
      %{"name" => "child", "parent" => "r"},
      %{"name" => "root", "ref" => "r"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items)
    child = item(results, 0)
    root = item(results, 1)

    assert child.parent_id == root.id
    assert root.parent_id == nil
    assert Catalog.count() == 2
  end