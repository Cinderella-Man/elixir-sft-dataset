  test "start_link registers the process under the given :name option" do
    name = :"agg_named_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Aggregate.start_link(name: name)

    assert {:ok, [event]} = Aggregate.execute(name, "acct:1", {:open, "Alice"})
    assert event.type == :account_opened
    assert Aggregate.state(name, "acct:1").status == :open
  end