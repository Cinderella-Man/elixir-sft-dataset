  test "empty query string behaves like absent query" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"q" => ""})
    assert length(data) == 5
  end