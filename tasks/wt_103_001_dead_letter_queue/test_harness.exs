defmodule DLQTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic time-based testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  setup do
    start_supervised!({Clock, 0})
    {:ok, pid} = DLQ.start_link(clock: &Clock.now/0)
    %{dlq: pid}
  end

  # -------------------------------------------------------
  # push / peek basics
  # -------------------------------------------------------

  test "push stores a message and peek returns it with retry_count 0", %{dlq: dlq} do
    assert {:ok, id} = DLQ.push(dlq, "orders", %{n: 1}, :timeout, %{source: "web"})
    assert is_binary(id) or is_reference(id) or is_integer(id)

    assert [entry] = DLQ.peek(dlq, "orders", 10)
    assert entry.id == id
    assert entry.message == %{n: 1}
    assert entry.error_reason == :timeout
    assert entry.metadata == %{source: "web"}
    assert entry.retry_count == 0
  end

  test "peek on an unknown or empty queue returns []", %{dlq: dlq} do
    assert DLQ.peek(dlq, "nope", 10) == []
  end

  test "push returns unique ids within the same queue", %{dlq: dlq} do
    {:ok, id1} = DLQ.push(dlq, "q", :a, :err, %{})
    {:ok, id2} = DLQ.push(dlq, "q", :b, :err, %{})
    {:ok, id3} = DLQ.push(dlq, "q", :c, :err, %{})
    assert Enum.uniq([id1, id2, id3]) == [id1, id2, id3]
  end

  test "peek respects count and returns oldest-first order", %{dlq: dlq} do
    {:ok, _} = DLQ.push(dlq, "q", :first, :err, %{})
    Clock.advance(1)
    {:ok, _} = DLQ.push(dlq, "q", :second, :err, %{})
    Clock.advance(1)
    {:ok, _} = DLQ.push(dlq, "q", :third, :err, %{})

    two = DLQ.peek(dlq, "q", 2)
    assert length(two) == 2
    assert Enum.map(two, & &1.message) == [:first, :second]

    all = DLQ.peek(dlq, "q", 10)
    assert Enum.map(all, & &1.message) == [:first, :second, :third]
  end

  # -------------------------------------------------------
  # retry — success removes the message
  # -------------------------------------------------------

  test "retry with a succeeding handler (:ok) removes the message", %{dlq: dlq} do
    {:ok, id} = DLQ.push(dlq, "q", %{payload: 42}, :boom, %{})

    test_pid = self()
    handler = fn msg -> send(test_pid, {:handled, msg}); :ok end

    assert :ok = DLQ.retry(dlq, "q", id, handler)
    assert_received {:handled, %{payload: 42}}
    assert DLQ.peek(dlq, "q", 10) == []
  end

  test "retry treats {:ok, term} as success and removes the message", %{dlq: dlq} do
    {:ok, id} = DLQ.push(dlq, "q", :msg, :boom, %{})
    assert :ok = DLQ.retry(dlq, "q", id, fn _ -> {:ok, :done} end)
    assert DLQ.peek(dlq, "q", 10) == []
  end

  test "retry only removes the retried message, others remain", %{dlq: dlq} do
    {:ok, id1} = DLQ.push(dlq, "q", :one, :err, %{})
    {:ok, _id2} = DLQ.push(dlq, "q", :two, :err, %{})

    assert :ok = DLQ.retry(dlq, "q", id1, fn _ -> :ok end)

    remaining = DLQ.peek(dlq, "q", 10)
    assert Enum.map(remaining, & &1.message) == [:two]
  end

  # -------------------------------------------------------
  # retry — failure keeps the message, bumps retry_count
  # -------------------------------------------------------

  test "retry with a failing handler keeps the message and increments retry_count", %{dlq: dlq} do
    {:ok, id} = DLQ.push(dlq, "q", :msg, :orig, %{})

    assert {:error, :boom} = DLQ.retry(dlq, "q", id, fn _ -> {:error, :boom} end)

    assert [entry] = DLQ.peek(dlq, "q", 10)
    assert entry.id == id
    assert entry.retry_count == 1
  end

  test "repeated failing retries accumulate the retry_count", %{dlq: dlq} do
    {:ok, id} = DLQ.push(dlq, "q", :msg, :orig, %{})
    fail = fn _ -> {:error, :again} end

    assert {:error, :again} = DLQ.retry(dlq, "q", id, fail)
    assert {:error, :again} = DLQ.retry(dlq, "q", id, fail)
    assert {:error, :again} = DLQ.retry(dlq, "q", id, fail)

    assert [entry] = DLQ.peek(dlq, "q", 10)
    assert entry.retry_count == 3
  end

  test "a raising handler does not crash the DLQ and keeps the message", %{dlq: dlq} do
    {:ok, id} = DLQ.push(dlq, "q", :msg, :orig, %{})

    assert {:error, _reason} =
             DLQ.retry(dlq, "q", id, fn _ -> raise "kaboom" end)

    assert Process.alive?(dlq)
    assert [entry] = DLQ.peek(dlq, "q", 10)
    assert entry.retry_count == 1

    # server still usable afterwards
    assert :ok = DLQ.retry(dlq, "q", id, fn _ -> :ok end)
    assert DLQ.peek(dlq, "q", 10) == []
  end

  test "retry on an unknown message id returns {:error, :not_found}", %{dlq: dlq} do
    assert {:error, :not_found} = DLQ.retry(dlq, "q", "no-such-id", fn _ -> :ok end)
    assert {:error, :not_found} =
             DLQ.retry(dlq, "missing-queue", "x", fn _ -> :ok end)
  end

  # -------------------------------------------------------
  # queue independence
  # -------------------------------------------------------

  test "different queues are completely independent", %{dlq: dlq} do
    {:ok, a_id} = DLQ.push(dlq, "a", :ma, :err, %{})
    {:ok, _b_id} = DLQ.push(dlq, "b", :mb, :err, %{})

    # failing retry on "a" must not touch "b"
    assert {:error, :x} = DLQ.retry(dlq, "a", a_id, fn _ -> {:error, :x} end)

    assert [ea] = DLQ.peek(dlq, "a", 10)
    assert ea.retry_count == 1

    assert [eb] = DLQ.peek(dlq, "b", 10)
    assert eb.retry_count == 0
    assert eb.message == :mb
  end

  # -------------------------------------------------------
  # purge
  # -------------------------------------------------------

  test "purge removes messages at/older than the given age and keeps newer ones", %{dlq: dlq} do
    # A pushed at t=0
    {:ok, _a} = DLQ.push(dlq, "q", :old, :err, %{})

    Clock.advance(1_000)
    # B pushed at t=1000
    {:ok, b} = DLQ.push(dlq, "q", :new, :err, %{})

    # now = 1000. A age = 1000 (>= 500 -> purged), B age = 0 (kept)
    assert {:ok, 1} = DLQ.purge(dlq, "q", 500)

    assert [entry] = DLQ.peek(dlq, "q", 10)
    assert entry.id == b
    assert entry.message == :new
  end

  test "purge returns 0 when nothing is old enough", %{dlq: dlq} do
    {:ok, _} = DLQ.push(dlq, "q", :m, :err, %{})
    Clock.advance(100)
    assert {:ok, 0} = DLQ.purge(dlq, "q", 1_000)
    assert length(DLQ.peek(dlq, "q", 10)) == 1
  end

  test "purge can clear the whole queue and counts everything removed", %{dlq: dlq} do
    {:ok, _} = DLQ.push(dlq, "q", :m1, :err, %{})
    {:ok, _} = DLQ.push(dlq, "q", :m2, :err, %{})
    {:ok, _} = DLQ.push(dlq, "q", :m3, :err, %{})

    Clock.advance(5_000)
    assert {:ok, 3} = DLQ.purge(dlq, "q", 1_000)
    assert DLQ.peek(dlq, "q", 10) == []
  end

  test "purge is scoped to a single queue", %{dlq: dlq} do
    {:ok, _} = DLQ.push(dlq, "a", :ma, :err, %{})
    {:ok, _} = DLQ.push(dlq, "b", :mb, :err, %{})

    Clock.advance(5_000)
    assert {:ok, 1} = DLQ.purge(dlq, "a", 1_000)

    assert DLQ.peek(dlq, "a", 10) == []
    assert [%{message: :mb}] = DLQ.peek(dlq, "b", 10)
  end
end