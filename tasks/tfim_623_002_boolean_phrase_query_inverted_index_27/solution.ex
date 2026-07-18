  test "accepts :name option for registration" do
    {:ok, _pid} = InvertedIndex.start_link(name: :bool_index)
    :ok = InvertedIndex.index(:bool_index, "a", %{body: "hello world"})
    assert InvertedIndex.search(:bool_index, {:term, "hello"}) == ["a"]
  end