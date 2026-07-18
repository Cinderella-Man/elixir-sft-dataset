  test "absent sort param defaults to ordering by id ascending" do
    assert {:ok, %{data: data, total: 6}} = Faceted.search(products(), %{})
    assert ids(data) == [1, 2, 3, 4, 5, 6]
  end