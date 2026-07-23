# Implement to green

Treat the ExUnit suite below as the full requirements document. Write the
code under test so the whole suite passes. Dependencies: only what the
tests already use (the standard library and OTP otherwise). Style:
`@moduledoc`, `@doc` + `@spec` on the public API, warning-free compile.

## The test suite

```elixir
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

    handler = fn msg ->
      send(test_pid, {:handled, msg})
      :ok
    end

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

  test "retry with a handler returning an unexpected value fails and keeps the message", %{
    dlq: dlq
  } do
    {:ok, id} = DLQ.push(dlq, "q", :msg, :orig, %{})

    assert {:error, _reason} = DLQ.retry(dlq, "q", id, fn _ -> :weird end)
    assert Process.alive?(dlq)

    assert [entry] = DLQ.peek(dlq, "q", 10)
    assert entry.id == id
    assert entry.message == :msg
    assert entry.retry_count == 1

    assert {:error, _other} = DLQ.retry(dlq, "q", id, fn _ -> {:not, :ok} end)
    assert [entry2] = DLQ.peek(dlq, "q", 10)
    assert entry2.retry_count == 2
  end

  test "purge removes a message whose age is exactly equal to older_than", %{dlq: dlq} do
    {:ok, exact} = DLQ.push(dlq, "q", :exact, :err, %{})

    Clock.advance(500)
    {:ok, younger} = DLQ.push(dlq, "q", :younger, :err, %{})

    Clock.advance(500)
    # now = 1000: :exact age = 1000 (== 1000 -> purged), :younger age = 500 (kept)
    assert {:ok, 1} = DLQ.purge(dlq, "q", 1_000)

    assert [entry] = DLQ.peek(dlq, "q", 10)
    assert entry.id == younger
    refute entry.id == exact
  end

  test "retry does not find a message id that lives in a different queue", %{dlq: dlq} do
    {:ok, a_id} = DLQ.push(dlq, "a", :ma, :err, %{})
    {:ok, _b_id} = DLQ.push(dlq, "b", :mb, :err, %{})

    test_pid = self()
    handler = fn msg -> send(test_pid, {:called, msg}) && :ok end

    assert {:error, :not_found} = DLQ.retry(dlq, "b", a_id, handler)
    refute_received {:called, _}

    assert [%{id: ^a_id, retry_count: 0, message: :ma}] = DLQ.peek(dlq, "a", 10)
    assert [%{message: :mb, retry_count: 0}] = DLQ.peek(dlq, "b", 10)
  end

  test "push ids are unique across different queues in the same server", %{dlq: dlq} do
    {:ok, a1} = DLQ.push(dlq, "a", :m1, :err, %{})
    {:ok, b1} = DLQ.push(dlq, "b", :m2, :err, %{})
    {:ok, a2} = DLQ.push(dlq, "a", :m3, :err, %{})
    {:ok, c1} = DLQ.push(dlq, "c", :m4, :err, %{})

    ids = [a1, b1, a2, c1]
    assert length(Enum.uniq(ids)) == 4

    # removing one id must leave the identically-positioned ids in other queues alone
    assert :ok = DLQ.retry(dlq, "a", a1, fn _ -> :ok end)
    assert [%{id: ^b1}] = DLQ.peek(dlq, "b", 10)
    assert [%{id: ^c1}] = DLQ.peek(dlq, "c", 10)
  end

  test "start_link registers the server under the given :name option" do
    name = :dlq_name_option_registration_test

    pid = start_supervised!({DLQ, [clock: &Clock.now/0, name: name]}, id: :named_dlq)

    assert Process.whereis(name) == pid
    assert {:ok, id} = DLQ.push(name, "q", :via_name, :err, %{k: 1})
    assert [entry] = DLQ.peek(name, "q", 10)
    assert entry.id == id
    assert entry.message == :via_name
    assert entry.metadata == %{k: 1}
  end

  test "peek with a count of 0 returns [] without removing anything", %{dlq: dlq} do
    {:ok, id} = DLQ.push(dlq, "q", :kept, :err, %{})

    assert DLQ.peek(dlq, "q", 0) == []
    assert [entry] = DLQ.peek(dlq, "q", 1)
    assert entry.id == id
    assert entry.message == :kept
  end

  # -------------------------------------------------------
  # default clock (no :clock option given)
  # -------------------------------------------------------

  # Spin until at least `min_ms` of real time has elapsed, so the ages the
  # default clock reports are known to sit inside a wide millisecond window.
  defp elapse_real_ms(min_ms) do
    spin_until(System.monotonic_time(:millisecond) + min_ms)
  end

  defp spin_until(deadline) do
    if System.monotonic_time(:millisecond) < deadline do
      spin_until(deadline)
    else
      :ok
    end
  end

  test "without a :clock option purge ages messages on a real millisecond clock" do
    dlq = start_supervised!({DLQ, []}, id: :default_clock_dlq)

    {:ok, _} = DLQ.push(dlq, "young", :m1, :err, %{})
    {:ok, _} = DLQ.push(dlq, "aged", :m2, :err, %{})

    elapse_real_ms(50)

    # Roughly 50 ms of real time has passed: no message is a full minute old,
    # so a 60_000 ms threshold must purge nothing.
    assert {:ok, 0} = DLQ.purge(dlq, "young", 60_000)
    assert [%{message: :m1}] = DLQ.peek(dlq, "young", 10)

    # The same elapsed time is well past a 20 ms threshold, so that purge
    # must remove the message.
    assert {:ok, 1} = DLQ.purge(dlq, "aged", 20)
    assert DLQ.peek(dlq, "aged", 10) == []
  end
end
```

Deliverable: the module(s) alone in a single file — not the tests.
