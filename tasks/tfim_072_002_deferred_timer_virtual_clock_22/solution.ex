  test "schedule hands out unique integer refs across cancelled and fired timers" do
    {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

    a = Clock.Fake.schedule(clock, [seconds: 1], fn -> :ok end)
    b = Clock.Fake.schedule(clock, [seconds: 2], fn -> :ok end)
    assert Clock.Fake.cancel(clock, b) == :ok
    assert Clock.Fake.advance(clock, seconds: 5) == [a]
    c = Clock.Fake.schedule(clock, [seconds: 1], fn -> :ok end)

    refs = [a, b, c]
    assert Enum.all?(refs, &is_integer/1)
    assert Enum.uniq(refs) == refs
  end