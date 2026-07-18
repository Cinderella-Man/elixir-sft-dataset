  test "accepts :name option for registration" do
    {:ok, _pid} = InvertedIndex.start_link(name: :bm25_index)
    :ok = InvertedIndex.index(:bm25_index, "doc1", %{body: "hello world"})
    assert length(InvertedIndex.search(:bm25_index, "hello")) == 1
  end