  test "each subscription returns a unique ref", %{bus: bus} do
    {:ok, ref1} = EventBus.subscribe(bus, "t", self())
    {:ok, ref2} = EventBus.subscribe(bus, "t", self())
    {:ok, ref3} = EventBus.subscribe(bus, "u", self())

    assert ref1 != ref2
    assert ref2 != ref3
  end