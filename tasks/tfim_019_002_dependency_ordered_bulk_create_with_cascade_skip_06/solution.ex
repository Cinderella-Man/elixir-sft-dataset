  test "resolves a multi-level dependency chain" do
    items = [
      %{"name" => "a", "ref" => "a"},
      %{"name" => "b", "ref" => "b", "parent" => "a"},
      %{"name" => "c", "parent" => "b"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items)
    a = item(results, 0)
    b = item(results, 1)
    c = item(results, 2)

    assert a.parent_id == nil
    assert b.parent_id == a.id
    assert c.parent_id == b.id
  end