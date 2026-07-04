  test "relevance ascending reverses the ranking" do
    assert {:ok, %{data: data}} =
             Ranked.search(products(), %{"q" => "trail", "order" => "asc"})

    assert ids(data) == [1, 2]
  end