  test "sort override to price descending keeps only matches" do
    assert {:ok, %{data: data}} =
             Ranked.search(products(), %{"q" => "run", "sort" => "price", "order" => "desc"})

    assert ids(data) == [2, 1]
  end