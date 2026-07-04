  test "partial mode still creates a valid dependent with the correct parent_id" do
    items = [
      %{"name" => "root", "ref" => "r"},
      %{"name" => "child", "parent" => "r"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items, partial: true)
    root = item(results, 0)
    child = item(results, 1)
    assert child.parent_id == root.id
    assert Catalog.count() == 2

    assert MapSet.new(Catalog.all()) == MapSet.new([root, child])
  end