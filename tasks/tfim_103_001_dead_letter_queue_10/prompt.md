# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule DLQ do
  @moduledoc """
  A dead letter queue GenServer.

  A dead letter queue is a place to park messages that failed processing so
  they can be inspected (`peek/3`), retried (`retry/4`), or purged (`purge/4`)
  later.

  Messages are grouped by an arbitrary `queue_name`. Different queues are
  completely independent — operating on one never affects another.

  Each stored message records the time it was pushed (via a configurable clock)
  and a retry count that starts at `0` and is incremented every time a retry
  fails.
  """

  use GenServer

  ## Client API

  @doc """
  Start the dead letter queue process.

  ## Options

    * `:clock` — a zero-arity function returning the current time in
      milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
    * `:name` — optional name for process registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    gen_opts =
      case name do
        nil -> []
        name -> [name: name]
      end

    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Record a failed `message` under `queue_name`.

  Returns `{:ok, message_id}` where `message_id` is unique within the server.
  """
  @spec push(GenServer.server(), term(), term(), term(), map()) :: {:ok, term()}
  def push(server, queue_name, message, error_reason, metadata)
      when is_map(metadata) do
    GenServer.call(server, {:push, queue_name, message, error_reason, metadata})
  end

  @doc """
  Return up to `count` messages held for `queue_name`, oldest-first, without
  removing them. Unknown or empty queues return `[]`.
  """
  @spec peek(GenServer.server(), term(), non_neg_integer()) :: [map()]
  def peek(server, queue_name, count)
      when is_integer(count) and count >= 0 do
    GenServer.call(server, {:peek, queue_name, count})
  end

  @doc """
  Re-attempt processing of one message by `message_id` within `queue_name`.

  `handler_fn` is invoked with the stored message. Success is `:ok` or
  `{:ok, term}`, in which case the message is removed and `:ok` is returned.
  Any other return value, an `{:error, reason}`, or a raised exception is a
  failure: the message stays, its retry count is incremented, and
  `{:error, reason}` is returned.
  """
  @spec retry(GenServer.server(), term(), term(), (term() -> term())) ::
          :ok | {:error, term()}
  def retry(server, queue_name, message_id, handler_fn)
      when is_function(handler_fn, 1) do
    GenServer.call(server, {:retry, queue_name, message_id, handler_fn})
  end

  @doc """
  Remove messages from `queue_name` whose age is at least `older_than`
  milliseconds. Returns `{:ok, purged_count}`.
  """
  @spec purge(GenServer.server(), term(), non_neg_integer()) ::
          {:ok, non_neg_integer()}
  def purge(server, queue_name, older_than)
      when is_integer(older_than) do
    GenServer.call(server, {:purge, queue_name, older_than})
  end

  ## Server callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    state = %{
      clock: clock,
      next_id: 0,
      # queue_name => list of entries, kept in oldest-first insertion order
      queues: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:push, queue_name, message, error_reason, metadata}, _from, state) do
    id = state.next_id

    entry = %{
      id: id,
      message: message,
      error_reason: error_reason,
      metadata: metadata,
      retry_count: 0,
      pushed_at: state.clock.()
    }

    queues = Map.update(state.queues, queue_name, [entry], fn entries -> entries ++ [entry] end)
    state = %{state | queues: queues, next_id: id + 1}

    {:reply, {:ok, id}, state}
  end

  @impl true
  def handle_call({:peek, queue_name, count}, _from, state) do
    entries =
      state.queues
      |> Map.get(queue_name, [])
      |> Enum.take(count)
      |> Enum.map(&public_entry/1)

    {:reply, entries, state}
  end

  @impl true
  def handle_call({:retry, queue_name, message_id, handler_fn}, _from, state) do
    entries = Map.get(state.queues, queue_name, [])

    case Enum.find(entries, fn entry -> entry.id == message_id end) do
      nil ->
        {:reply, {:error, :not_found}, state}

      entry ->
        case run_handler(handler_fn, entry.message) do
          :success ->
            new_entries = Enum.reject(entries, fn e -> e.id == message_id end)
            state = put_queue(state, queue_name, new_entries)
            {:reply, :ok, state}

          {:failure, reason} ->
            new_entries =
              Enum.map(entries, fn
                %{id: ^message_id} = e -> %{e | retry_count: e.retry_count + 1}
                e -> e
              end)

            state = put_queue(state, queue_name, new_entries)
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:purge, queue_name, older_than}, _from, state) do
    entries = Map.get(state.queues, queue_name, [])
    now = state.clock.()

    {kept, purged} =
      Enum.split_with(entries, fn entry ->
        now - entry.pushed_at < older_than
      end)

    state = put_queue(state, queue_name, kept)
    {:reply, {:ok, length(purged)}, state}
  end

  ## Helpers

  defp run_handler(handler_fn, message) do
    case handler_fn.(message) do
      :ok -> :success
      {:ok, _term} -> :success
      {:error, reason} -> {:failure, reason}
      other -> {:failure, {:unexpected_return, other}}
    end
  rescue
    exception -> {:failure, {:handler_raised, exception}}
  catch
    kind, value -> {:failure, {kind, value}}
  end

  defp put_queue(state, queue_name, entries) do
    queues =
      case entries do
        [] -> Map.delete(state.queues, queue_name)
        _ -> Map.put(state.queues, queue_name, entries)
      end

    %{state | queues: queues}
  end

  defp public_entry(entry) do
    Map.take(entry, [:id, :message, :error_reason, :metadata, :retry_count])
  end
end
```

## Test harness — implement the `# TODO` test

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
    # TODO
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
```
