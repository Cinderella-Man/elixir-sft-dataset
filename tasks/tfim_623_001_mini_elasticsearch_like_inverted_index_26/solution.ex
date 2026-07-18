  test "accepts :name option for registration" do
    {:ok, _pid} = InvertedIndex.start_link(name: :my_index)

    :ok = InvertedIndex.index(:my_index, "doc1", %{body: "hello world"})
    results = InvertedIndex.search(:my_index, "hello")
    assert length(results) == 1
  end