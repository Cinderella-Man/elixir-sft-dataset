  test "unregister returns error for an unknown job", %{s: s} do
    assert {:error, :not_found} = Scheduler.unregister(s, "nope")
  end