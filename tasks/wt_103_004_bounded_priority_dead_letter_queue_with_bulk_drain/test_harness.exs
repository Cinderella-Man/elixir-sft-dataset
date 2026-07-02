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

    handler = fn msg -> Recorder.record(msg); :ok end
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
end