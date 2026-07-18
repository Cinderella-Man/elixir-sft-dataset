  test "start_link registers the process under the given :name option" do
    name = :inventory_named_process_test
    {:ok, _pid} = InventoryAggregate.start_link(name: name)

    assert {:ok, [event]} =
             InventoryAggregate.execute(name, "prod:1", {:register, "Widget", "WDG-001"})

    assert event.type == :product_registered
    assert InventoryAggregate.state(name, "prod:1").status == :registered
  end