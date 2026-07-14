defmodule DedupDLQTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent
    def start_link(initial \\ 0), do: Agent.start_link(fn -> initial end, name: __MODULE__)
    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
  end

  setup do
    start_supervised!({Clock, 0})
    {:ok, pid} = DedupDLQ.start_link(clock: &Clock.now/0)
    %{dlq: pid}
  end

  test "first push creates a new entry with occurrences 1", %{dlq: dlq} do
    assert {:ok, :new, id} = DedupDLQ.push(dlq, "orders", "k1", %{n: 1}, :timeout, %{src: "web"})
    assert [e] = DedupDLQ.peek(dlq, "orders", 10)
    assert e.id == id
    assert e.dedup_key == "k1"
    assert e.occurrences == 1
    assert e.retry_count == 0
    assert e.first_seen == 0
    assert e.last_seen == 0
  end

  test "peek on unknown queue returns []", %{dlq: dlq} do
    assert DedupDLQ.peek(dlq, "nope", 10) == []
  end

  test "repeated key coalesces: same id, bumped count, latest data", %{dlq: dlq} do
    {:ok, :new, id} = DedupDLQ.push(dlq, "q", "k", :first, :err_a, %{v: 1})
    Clock.advance(100)
    assert {:ok, :duplicate, ^id} = DedupDLQ.push(dlq, "q", "k", :second, :err_b, %{v: 2})

    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.id == id
    assert e.occurrences == 2
    assert e.message == :second
    assert e.error_reason == :err_b
    assert e.metadata == %{v: 2}
    assert e.first_seen == 0
    assert e.last_seen == 100
  end

  test "different keys are independent entries", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "a", :ma, :err, %{})
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "b", :mb, :err, %{})
    assert length(DedupDLQ.peek(dlq, "q", 10)) == 2
  end

  test "peek orders oldest-first by first_seen", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "a", :first, :err, %{})
    Clock.advance(1)
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "b", :second, :err, %{})
    # re-push "a" as duplicate — must NOT reorder it to the back
    Clock.advance(1)
    {:ok, :duplicate, _} = DedupDLQ.push(dlq, "q", "a", :first, :err, %{})

    assert Enum.map(DedupDLQ.peek(dlq, "q", 10), & &1.dedup_key) == ["a", "b"]
  end

  test "peek truncates to count, keeping the oldest entries", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "a", :ma, :err, %{})
    Clock.advance(1)
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "b", :mb, :err, %{})
    Clock.advance(1)
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "c", :mc, :err, %{})

    assert Enum.map(DedupDLQ.peek(dlq, "q", 2), & &1.dedup_key) == ["a", "b"]
    assert Enum.map(DedupDLQ.peek(dlq, "q", 1), & &1.dedup_key) == ["a"]
    assert DedupDLQ.peek(dlq, "q", 0) == []
    # peeking is non-destructive: all three are still queued
    assert length(DedupDLQ.peek(dlq, "q", 3)) == 3
  end

  test "retry success removes the coalesced entry", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "k", :m, :err, %{})
    assert :ok = DedupDLQ.retry(dlq, "q", "k", fn _ -> :ok end)
    assert DedupDLQ.peek(dlq, "q", 10) == []
  end

  test "retry failure keeps entry and bumps retry_count (not occurrences)", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "k", :m, :err, %{})
    assert {:error, :boom} = DedupDLQ.retry(dlq, "q", "k", fn _ -> {:error, :boom} end)
    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
    assert e.occurrences == 1
  end

  test "duplicate push after a failed retry preserves retry_count", %{dlq: dlq} do
    {:ok, :new, id} = DedupDLQ.push(dlq, "q", "k", :first, :err_a, %{v: 1})
    assert {:error, :boom} = DedupDLQ.retry(dlq, "q", "k", fn _ -> {:error, :boom} end)

    Clock.advance(30)
    assert {:ok, :duplicate, ^id} = DedupDLQ.push(dlq, "q", "k", :second, :err_b, %{v: 2})

    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
    assert e.occurrences == 2
    assert e.id == id
    assert e.first_seen == 0
    assert e.last_seen == 30
    assert e.message == :second
  end

  test "raising handler counts as failure without crashing", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "k", :m, :err, %{})
    assert {:error, _} = DedupDLQ.retry(dlq, "q", "k", fn _ -> raise "x" end)
    assert Process.alive?(dlq)
    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
  end

  test "retry on unknown dedup key returns :not_found", %{dlq: dlq} do
    assert {:error, :not_found} = DedupDLQ.retry(dlq, "q", "nope", fn _ -> :ok end)
  end

  test "purge is based on last_seen; a recent duplicate protects the entry", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "stale", :m, :err, %{})
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "fresh", :m, :err, %{})

    Clock.advance(100)
    # refresh "fresh" so its last_seen is recent
    {:ok, :duplicate, _} = DedupDLQ.push(dlq, "q", "fresh", :m, :err, %{})

    Clock.advance(20)
    # now = 120: "stale" last_seen 0 (age 120 >= 50 -> purged),
    #            "fresh" last_seen 100 (age 20 < 50 -> kept)
    assert {:ok, 1} = DedupDLQ.purge(dlq, "q", 50)
    assert [e] = DedupDLQ.peek(dlq, "q", 10)
    assert e.dedup_key == "fresh"
  end

  test "queues are independent for the same dedup key", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "a", "k", :ma, :err, %{})
    {:ok, :new, _} = DedupDLQ.push(dlq, "b", "k", :mb, :err, %{})
    assert [ea] = DedupDLQ.peek(dlq, "a", 10)
    assert [eb] = DedupDLQ.peek(dlq, "b", 10)
    assert ea.message == :ma
    assert eb.message == :mb
  end
end
