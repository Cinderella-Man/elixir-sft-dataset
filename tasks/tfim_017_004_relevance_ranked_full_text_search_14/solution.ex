  test "punctuated, capitalized query tokenizes into bare alphanumeric tokens" do
    assert {:ok, %{data: data}} = Ranked.search(products(), %{"q" => "Running, shoes!"})

    # tokens ["running", "shoes"]
    # p1: name running(3)+shoes(3)=6, desc running(1)+shoes(1)=2 -> 8
    # p2: name 0, desc running(1) only ("shoe" does not start with "shoes") -> 1
    assert ids(data) == [1, 2]
    assert Enum.map(data, & &1.score) == [8, 1]
  end