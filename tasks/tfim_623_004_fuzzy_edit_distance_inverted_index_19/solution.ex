  test "accepts a :name option for registration" do
    {:ok, _pid} = FuzzyIndex.start_link(name: :fuzzy_index_reg)

    :ok = FuzzyIndex.index(:fuzzy_index_reg, "doc1", "hello world")
    assert length(FuzzyIndex.search(:fuzzy_index_reg, "hello")) == 1
  end