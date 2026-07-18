  test "start_link registers the process under the given :name" do
    name = :"counter_name_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Counter.start_link(name: name)
    assert :ok = Counter.increment(name, :a, 3)
    assert :ok = Counter.decrement(name, :a, 1)
    assert Counter.value(name) == 2
    assert Counter.state(name) == %{p: %{a: 3}, n: %{a: 1}}
  end