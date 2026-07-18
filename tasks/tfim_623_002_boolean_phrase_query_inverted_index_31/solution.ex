  test "every documented default stop word is excluded from the index", _ctx do
    {:ok, idx} = InvertedIndex.start_link([])

    defaults = ~w(the a an is are was were in on at to of and or it this that for with
                as by not be has had have do does did but if from)

    text = Enum.join(defaults, " ") <> " sentinel"
    :ok = InvertedIndex.index(idx, "a", %{body: text})

    assert InvertedIndex.stats(idx).term_count == 1
    assert InvertedIndex.search(idx, {:term, "sentinel"}) == ["a"]

    for word <- defaults do
      assert InvertedIndex.search(idx, {:term, word}) == [], "#{word} was indexed"
    end
  end