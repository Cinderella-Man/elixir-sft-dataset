  test "price is serialized as a two-decimal dollar string" do
    assert {:ok, %{data: [item]}} =
             KeysetSearch.search(products(), %{"category" => "outdoors", "sort" => "id"})

    assert item.price == "199.99"
  end