# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule PriorityDLQTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent
    def start_link(initial \\ 0), do: Agent.start_link(fn -> initial end, name: __MODULE__)
    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
  end

  defmodule Recorder do
    use Agent
    def start_link(_ \\ nil), do: Agent.start_link(fn -> [] end, name: __MODULE__)
    def record(m), do: Agent.update(__MODULE__, &[m | &1])
    def order, do: Agent.get(__MODULE__, &Enum.reverse(&1))
  end

  setup do
    start_supervised!({Clock, 0})
    start_supervised!(Recorder)
    {:ok, pid} = PriorityDLQ.start_link(clock: &Clock.now/0)
    %{dlq: pid}
  end

  test "push stores with priority and retry_count 0; peek returns it", %{dlq: dlq} do
    assert {:ok, id} = PriorityDLQ.push(dlq, "q", %{n: 1}, :timeout, %{s: "web"}, :normal)
    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.id == id
    assert e.priority == :normal
    assert e.retry_count == 0
  end

  test "peek on unknown queue returns []", %{dlq: dlq} do
    assert PriorityDLQ.peek(dlq, "nope", 10) == []
  end

  test "peek orders by priority then FIFO within a priority", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :l1, :err, %{}, :low)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :h1, :err, %{}, :high)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :n1, :err, %{}, :normal)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :h2, :err, %{}, :high)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :l2, :err, %{}, :low)

    assert Enum.map(PriorityDLQ.peek(dlq, "q", 10), & &1.message) ==
             [:h1, :h2, :n1, :l1, :l2]
  end

  test "peek respects count in priority order", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :l1, :err, %{}, :low)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :h1, :err, %{}, :high)
    assert Enum.map(PriorityDLQ.peek(dlq, "q", 1), & &1.message) == [:h1]
  end

  test "capacity is enforced per queue and rejects when full (nothing stored)", %{} do
    {:ok, dlq} = PriorityDLQ.start_link(clock: &Clock.now/0, capacity: 2)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :a, :err, %{}, :low)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :b, :err, %{}, :low)
    assert {:error, :full} = PriorityDLQ.push(dlq, "q", :c, :err, %{}, :high)
    assert length(PriorityDLQ.peek(dlq, "q", 10)) == 2

    # other queue has its own budget
    assert {:ok, _} = PriorityDLQ.push(dlq, "other", :d, :err, %{}, :low)
  end

  test "drain visits in priority order and reports processed ids in that order", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :l1, :err, %{}, :low)
    {:ok, hid} = PriorityDLQ.push(dlq, "q", :h1, :err, %{}, :high)
    {:ok, nid} = PriorityDLQ.push(dlq, "q", :n1, :err, %{}, :normal)

    handler = fn msg ->
      Recorder.record(msg)
      :ok
    end

    assert {:ok, stats} = PriorityDLQ.drain(dlq, "q", handler, 2)

    assert Recorder.order() == [:h1, :n1]
    assert stats.succeeded == 2
    assert stats.failed == 0
    assert stats.processed == [hid, nid]

    # low priority one remains
    assert Enum.map(PriorityDLQ.peek(dlq, "q", 10), & &1.message) == [:l1]
  end

  test "drain removes successes and keeps failures (bumping retry_count)", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :ok_msg, :err, %{}, :high)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :fail_msg, :err, %{}, :normal)

    handler = fn
      :ok_msg -> :ok
      :fail_msg -> {:error, :boom}
    end

    assert {:ok, stats} = PriorityDLQ.drain(dlq, "q", handler, 10)
    assert stats.succeeded == 1
    assert stats.failed == 1

    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.message == :fail_msg
    assert e.retry_count == 1
  end

  test "a raising handler during drain does not crash the process", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :boom, :err, %{}, :high)
    assert {:ok, stats} = PriorityDLQ.drain(dlq, "q", fn _ -> raise "x" end, 10)
    assert stats.failed == 1
    assert Process.alive?(dlq)
    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
  end

  test "purge removes by age", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :old, :err, %{}, :high)
    Clock.advance(1000)
    {:ok, b} = PriorityDLQ.push(dlq, "q", :new, :err, %{}, :low)

    assert {:ok, 1} = PriorityDLQ.purge(dlq, "q", 500)
    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.id == b
  end

  test "queues are independent", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "a", :ma, :err, %{}, :high)
    {:ok, _} = PriorityDLQ.push(dlq, "b", :mb, :err, %{}, :low)

    assert {:ok, %{succeeded: 1}} = PriorityDLQ.drain(dlq, "a", fn _ -> :ok end, 10)
    assert PriorityDLQ.peek(dlq, "a", 10) == []
    assert [%{message: :mb}] = PriorityDLQ.peek(dlq, "b", 10)
  end

  test "peek entries expose error_reason and metadata as pushed", %{dlq: dlq} do
    {:ok, id} = PriorityDLQ.push(dlq, "q", %{n: 7}, {:timeout, 5000}, %{source: "web"}, :high)

    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.id == id
    assert e.message == %{n: 7}
    assert e.error_reason == {:timeout, 5000}
    assert e.metadata == %{source: "web"}
    assert e.priority == :high
    assert e.retry_count == 0
  end

  test "drain treats {:ok, term} as success and removes the entry", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :m1, :err, %{}, :high)

    assert {:ok, stats} = PriorityDLQ.drain(dlq, "q", fn _ -> {:ok, :handled} end, 10)
    assert stats.succeeded == 1
    assert stats.failed == 0
    assert PriorityDLQ.peek(dlq, "q", 10) == []
  end

  test "drain treats an unexpected handler return as failure and keeps the entry", %{dlq: dlq} do
    {:ok, id} = PriorityDLQ.push(dlq, "q", :m1, :err, %{}, :normal)

    assert {:ok, stats} = PriorityDLQ.drain(dlq, "q", fn _ -> :something_else end, 10)
    assert stats.succeeded == 0
    assert stats.failed == 1
    assert stats.processed == [id]

    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.id == id
    assert e.retry_count == 1
  end

  test "purge removes entries whose age is exactly older_than", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :exact, :err, %{}, :high)
    Clock.advance(500)
    {:ok, younger} = PriorityDLQ.push(dlq, "q", :younger, :err, %{}, :low)

    assert {:ok, 1} = PriorityDLQ.purge(dlq, "q", 500)
    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.id == younger
  end

  test "capacity defaults to :infinity so pushes are never rejected", %{} do
    {:ok, dlq} = PriorityDLQ.start_link(clock: &Clock.now/0)

    for n <- 1..50 do
      assert {:ok, _} = PriorityDLQ.push(dlq, "q", {:m, n}, :err, %{}, :low)
    end

    assert length(PriorityDLQ.peek(dlq, "q", 100)) == 50
  end

  test "a throwing handler during drain counts as failure and keeps the entry", %{dlq: dlq} do
    {:ok, id} = PriorityDLQ.push(dlq, "q", :thrower, :err, %{}, :high)

    assert {:ok, stats} = PriorityDLQ.drain(dlq, "q", fn _ -> throw(:nope) end, 10)
    assert stats.succeeded == 0
    assert stats.failed == 1
    assert Process.alive?(dlq)

    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.id == id
    assert e.retry_count == 1
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
