  test "all/0 reflects rollback: stores nothing on all-or-nothing failure" do
    items = [%{"name" => "ok"}, %{"name" => ""}]
    assert {:error, _results} = Catalog.bulk_create(items)
    assert Catalog.all() == []
  end