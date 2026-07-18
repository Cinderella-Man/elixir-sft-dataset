  test "start_link registers the process under the given :name option" do
    name = :"agg_#{System.unique_integer([:positive])}"
    assert {:ok, _pid} = SubscriptionAggregate.start_link(name: name)

    assert {:ok, [event]} = SubscriptionAggregate.execute(name, "sub:1", {:create, "premium"})
    assert event.type == :subscription_created
    assert SubscriptionAggregate.state(name, "sub:1").status == :pending
  end