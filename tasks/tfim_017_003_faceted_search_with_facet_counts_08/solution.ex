  test "name search composes with facets" do
    assert {:ok, %{data: data, total: 1}} =
             Faceted.search(products(), %{"name" => "keyboard"})

    assert ids(data) == [4]
  end