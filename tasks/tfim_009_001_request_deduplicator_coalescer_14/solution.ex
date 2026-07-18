  test "registers under the :name option and is callable by that name" do
    name = :"dedup_named_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Dedup.start_link(name: name)
    assert {:ok, 7} = Dedup.execute(name, "k", fn -> {:ok, 7} end)
  end