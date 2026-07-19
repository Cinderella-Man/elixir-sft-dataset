# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule ClockV1Test do
  use ExUnit.Case, async: false

  # Collect `n` messages from the mailbox in FIFO (delivery) order, so we can
  # assert on the *order* in which scheduled callbacks fired.
  defp drain(0), do: []

  defp drain(n) do
    receive do
      msg -> [msg | drain(n - 1)]
    after
      500 -> flunk("timed out waiting for #{n} more message(s)")
    end
  end

  # -------------------------------------------------------
  # Clock.Real
  # -------------------------------------------------------

  describe "Clock.Real" do
    test "now/0 returns a DateTime close to the actual current UTC time" do
      before = DateTime.utc_now()
      result = Clock.Real.now()
      after_ = DateTime.utc_now()

      assert %DateTime{} = result
      assert DateTime.compare(result, before) in [:gt, :eq]
      assert DateTime.compare(result, after_) in [:lt, :eq]
    end
  end

  # -------------------------------------------------------
  # Clock.Fake — basic time control
  # -------------------------------------------------------

  describe "Clock.Fake basics" do
    setup do
      initial = ~U[2024-06-15 12:00:00Z]
      {:ok, pid} = Clock.Fake.start_link(initial: initial)
      %{clock: pid, initial: initial}
    end

    test "now/1 returns the frozen datetime", %{clock: clock, initial: initial} do
      assert Clock.Fake.now(clock) == initial
    end

    test "advance moves virtual time forward", %{clock: clock, initial: initial} do
      Clock.Fake.advance(clock, hours: 1, minutes: 30)
      assert Clock.Fake.now(clock) == DateTime.add(initial, 90 * 60, :second)
    end

    test "advance is cumulative", %{clock: clock, initial: initial} do
      Clock.Fake.advance(clock, seconds: 10)
      Clock.Fake.advance(clock, seconds: 20)
      assert Clock.Fake.now(clock) == DateTime.add(initial, 30, :second)
    end
  end

  # -------------------------------------------------------
  # Clock.Fake — deferred timers
  # -------------------------------------------------------

  describe "Clock.Fake deferred timers" do
    setup do
      {:ok, pid} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])
      %{clock: pid}
    end

    test "a timer fires only once virtual time reaches its due instant", %{clock: clock} do
      test = self()
      Clock.Fake.schedule(clock, [seconds: 10], fn -> send(test, :fired) end)

      Clock.Fake.advance(clock, seconds: 5)
      refute_receive :fired, 50

      Clock.Fake.advance(clock, seconds: 5)
      assert_receive :fired
    end

    test "advance returns the refs of timers it fired", %{clock: clock} do
      test = self()
      ref = Clock.Fake.schedule(clock, [seconds: 3], fn -> send(test, :ok) end)
      assert Clock.Fake.advance(clock, seconds: 5) == [ref]
    end

    test "timers fire in chronological order regardless of registration order", %{clock: clock} do
      test = self()
      # Registered late-first, then early — firing must reorder to :b before :a.
      Clock.Fake.schedule(clock, [seconds: 10], fn -> send(test, :a) end)
      Clock.Fake.schedule(clock, [seconds: 5], fn -> send(test, :b) end)

      fired = Clock.Fake.advance(clock, seconds: 20)
      assert length(fired) == 2
      assert drain(2) == [:b, :a]
    end

    test "cancel prevents a pending timer from firing", %{clock: clock} do
      test = self()
      ref = Clock.Fake.schedule(clock, [seconds: 5], fn -> send(test, :should_not_fire) end)

      assert Clock.Fake.cancel(clock, ref) == :ok
      assert Clock.Fake.advance(clock, seconds: 10) == []
      refute_receive :should_not_fire, 50
    end

    test "cancel returns :error for an unknown or already-fired ref", %{clock: clock} do
      ref = Clock.Fake.schedule(clock, [seconds: 1], fn -> :ok end)
      Clock.Fake.advance(clock, seconds: 2)
      assert Clock.Fake.cancel(clock, ref) == :error
      assert Clock.Fake.cancel(clock, 9999) == :error
    end

    test "pending/1 tracks outstanding timers", %{clock: clock} do
      Clock.Fake.schedule(clock, [seconds: 5], fn -> :ok end)
      Clock.Fake.schedule(clock, [seconds: 10], fn -> :ok end)
      assert Clock.Fake.pending(clock) == 2

      Clock.Fake.advance(clock, seconds: 5)
      assert Clock.Fake.pending(clock) == 1

      Clock.Fake.advance(clock, seconds: 10)
      assert Clock.Fake.pending(clock) == 0
    end
  end

  # -------------------------------------------------------
  # Clock.now/1 dispatch
  # -------------------------------------------------------

  describe "Clock.now/1 unified dispatch" do
    test "dispatches to Clock.Real when given the module atom" do
      assert %DateTime{} = Clock.now(Clock.Real)
    end

    test "dispatches to Clock.Fake when given a pid" do
      target = ~U[2025-03-20 09:30:00Z]
      {:ok, pid} = Clock.Fake.start_link(initial: target)
      assert Clock.now(pid) == target
    end

    test "dispatches to Clock.Fake when given a registered name" do
      target = ~U[2025-03-20 09:30:00Z]
      {:ok, _pid} = Clock.Fake.start_link(initial: target, name: :v1_named_clock)
      assert Clock.now(:v1_named_clock) == target
    end
  end

  # -------------------------------------------------------
  # Isolation
  # -------------------------------------------------------

  describe "isolation" do
    test "two clocks and their timers are independent" do
      test = self()
      {:ok, a} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])
      {:ok, b} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

      Clock.Fake.schedule(a, [seconds: 5], fn -> send(test, :a_fired) end)
      Clock.Fake.schedule(b, [seconds: 5], fn -> send(test, :b_fired) end)

      Clock.Fake.advance(a, seconds: 10)
      assert_receive :a_fired
      refute_receive :b_fired, 50
      assert Clock.Fake.pending(b) == 1
      assert Clock.Fake.now(b) == ~U[2024-01-01 00:00:00Z]
    end
  end

  # -------------------------------------------------------
  # Injection pattern
  # -------------------------------------------------------

  describe "dependency injection pattern" do
    defmodule Reminder do
      @doc "Schedules a reminder callback `after` a delay, driven by the injected clock."
      def remind_in(clock, duration, fun), do: Clock.Fake.schedule(clock, duration, fun)
    end

    test "a scheduled reminder fires at the right virtual time" do
      test = self()
      {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-06-01 09:00:00Z])
      Reminder.remind_in(clock, [hours: 2], fn -> send(test, :ding) end)

      Clock.Fake.advance(clock, hours: 1)
      refute_receive :ding, 50
      Clock.Fake.advance(clock, hours: 1)
      assert_receive :ding
    end
  end

  test "timers due at the same instant fire in registration order" do
    test = self()
    {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

    r1 = Clock.Fake.schedule(clock, [seconds: 5], fn -> send(test, :first) end)
    r2 = Clock.Fake.schedule(clock, [seconds: 5], fn -> send(test, :second) end)

    assert Clock.Fake.advance(clock, seconds: 5) == [r1, r2]
    assert drain(2) == [:first, :second]
  end

  test "a zero-duration timer stays pending until an advance call fires it" do
    test = self()
    {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

    ref = Clock.Fake.schedule(clock, [seconds: 0], fn -> send(test, :now_due) end)
    refute_receive :now_due, 50
    assert Clock.Fake.pending(clock) == 1

    assert Clock.Fake.advance(clock, seconds: 0) == [ref]
    assert_receive :now_due
  end

  test "start_link without :initial starts at the documented default instant" do
    {:ok, clock} = Clock.Fake.start_link([])
    assert Clock.Fake.now(clock) == ~U[2024-01-01 00:00:00Z]
  end

  test "advance returns fired refs chronologically rather than by registration order" do
    {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

    late = Clock.Fake.schedule(clock, [seconds: 10], fn -> :ok end)
    early = Clock.Fake.schedule(clock, [seconds: 5], fn -> :ok end)

    assert Clock.Fake.advance(clock, seconds: 20) == [early, late]
  end

  test "advance supports singular unit names and day units" do
    {:ok, clock} = Clock.Fake.start_link(initial: ~U[2024-01-01 00:00:00Z])

    Clock.Fake.advance(clock, day: 1, hour: 1, minute: 1, second: 1)
    assert Clock.Fake.now(clock) == ~U[2024-01-02 01:01:01Z]

    Clock.Fake.advance(clock, days: 2, minutes: 1)
    assert Clock.Fake.now(clock) == ~U[2024-01-04 01:02:01Z]
  end

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
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
