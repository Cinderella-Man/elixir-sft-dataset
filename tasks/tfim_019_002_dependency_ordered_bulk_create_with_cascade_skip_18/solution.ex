  test "ids auto-increment across items and across successive batches" do
    assert {:ok, first} = Catalog.bulk_create([%{"name" => "one"}, %{"name" => "two"}])
    a = item(first, 0)
    b = item(first, 1)
    assert is_integer(a.id)
    assert b.id == a.id + 1

    assert {:ok, second} = Catalog.bulk_create([%{"name" => "three"}])
    c = item(second, 0)
    assert c.id == b.id + 1
    assert Catalog.get(c.id) == c
    assert Catalog.count() == 3
  end