  test "score is included and price is a two-decimal dollar string" do
    assert {:ok, %{data: [item | _]}} = Ranked.search(products(), %{"q" => "running shoe"})

    assert item.score == 8
    assert item.price == "89.99"
  end