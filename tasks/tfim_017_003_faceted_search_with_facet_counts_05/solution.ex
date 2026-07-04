  test "tags filter is AND" do
    assert {:ok, %{data: data, total: 2}} =
             Faceted.search(products(), %{"tags" => ["wired", "office"], "sort" => "id"})

    assert ids(data) == [4, 5]
  end