  test "next_run returns error for unknown job", %{s: s} do
    assert {:error, :not_found} = Scheduler.next_run(s, "nope")
  end