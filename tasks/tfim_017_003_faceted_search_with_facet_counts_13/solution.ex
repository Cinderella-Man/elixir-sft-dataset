  test "price is serialized as a two-decimal dollar string" do
    assert {:ok, %{data: [item]}} = Faceted.search(products(), %{"name" => "usb"})
    assert item.price == "9.99"
  end