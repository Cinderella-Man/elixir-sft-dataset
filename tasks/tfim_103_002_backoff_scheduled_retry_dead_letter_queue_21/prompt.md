# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule BackoffDLQ do
  @moduledoc """
  A dead letter queue with exponential backoff-gated retries and a terminal
  `:dead` state after `:max_attempts` failures.
  """

  use GenServer

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Pushes a failed `message` with backoff-scheduled retry. Returns `{:ok, id}`."
  @spec push(GenServer.server(), term(), term(), term(), map()) :: {:ok, term()}
  def push(server, queue_name, message, error_reason, metadata) when is_map(metadata) do
    GenServer.call(server, {:push, queue_name, message, error_reason, metadata})
  end

  @spec peek(GenServer.server(), term(), non_neg_integer()) :: [map()]
  def peek(server, queue_name, count) when is_integer(count) and count >= 0 do
    GenServer.call(server, {:peek, queue_name, count})
  end

  @spec ready(GenServer.server(), term(), non_neg_integer()) :: [map()]
  def ready(server, queue_name, count) when is_integer(count) and count >= 0 do
    GenServer.call(server, {:ready, queue_name, count})
  end

  @spec retry(GenServer.server(), term(), term(), (term() -> term())) ::
          :ok | {:error, term()} | {:error, :not_ready, non_neg_integer()}
  def retry(server, queue_name, message_id, handler_fn) when is_function(handler_fn, 1) do
    GenServer.call(server, {:retry, queue_name, message_id, handler_fn})
  end

  @spec purge(GenServer.server(), term(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def purge(server, queue_name, older_than) when is_integer(older_than) do
    GenServer.call(server, {:purge, queue_name, older_than})
  end

  ## Server callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    state = %{
      clock: clock,
      base: Keyword.get(opts, :base_backoff_ms, 1000),
      max_attempts: Keyword.get(opts, :max_attempts, 5),
      next_id: 0,
      queues: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:push, queue, message, error_reason, metadata}, _from, state) do
    id = state.next_id
    now = state.clock.()

    entry = %{
      id: id,
      message: message,
      error_reason: error_reason,
      metadata: metadata,
      retry_count: 0,
      status: :pending,
      pushed_at: now,
      next_retry_at: now
    }

    queues = Map.update(state.queues, queue, [entry], fn es -> es ++ [entry] end)
    {:reply, {:ok, id}, %{state | queues: queues, next_id: id + 1}}
  end

  def handle_call({:peek, queue, count}, _from, state) do
    entries = state.queues |> Map.get(queue, []) |> Enum.take(count) |> Enum.map(&public/1)
    {:reply, entries, state}
  end

  def handle_call({:ready, queue, count}, _from, state) do
    now = state.clock.()

    entries =
      state.queues
      |> Map.get(queue, [])
      |> Enum.filter(fn e -> e.status == :pending and now >= e.next_retry_at end)
      |> Enum.take(count)
      |> Enum.map(&public/1)

    {:reply, entries, state}
  end

  def handle_call({:retry, queue, id, handler}, _from, state) do
    entries = Map.get(state.queues, queue, [])

    case Enum.find(entries, &(&1.id == id)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: :dead} ->
        {:reply, {:error, :dead}, state}

      entry ->
        now = state.clock.()

        if now < entry.next_retry_at do
          {:reply, {:error, :not_ready, entry.next_retry_at - now}, state}
        else
          case run_handler(handler, entry.message) do
            :success ->
              new = Enum.reject(entries, &(&1.id == id))
              {:reply, :ok, put_queue(state, queue, new)}

            {:failure, reason} ->
              rc = entry.retry_count + 1

              updated =
                if rc >= state.max_attempts do
                  %{entry | retry_count: rc, status: :dead}
                else
                  delay = state.base * pow2(rc - 1)
                  %{entry | retry_count: rc, next_retry_at: now + delay}
                end

              new = Enum.map(entries, fn e -> if e.id == id, do: updated, else: e end)
              {:reply, {:error, reason}, put_queue(state, queue, new)}
          end
        end
    end
  end

  def handle_call({:purge, queue, older_than}, _from, state) do
    entries = Map.get(state.queues, queue, [])
    now = state.clock.()
    {kept, purged} = Enum.split_with(entries, fn e -> now - e.pushed_at < older_than end)
    {:reply, {:ok, length(purged)}, put_queue(state, queue, kept)}
  end

  ## Helpers

  defp run_handler(handler, message) do
    case handler.(message) do
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

  defp pow2(n), do: :math.pow(2, n) |> round()

  defp put_queue(state, queue, entries) do
    queues =
      case entries do
        [] -> Map.delete(state.queues, queue)
        _ -> Map.put(state.queues, queue, entries)
      end

    %{state | queues: queues}
  end

  defp public(e) do
    Map.take(e, [
      :id,
      :message,
      :error_reason,
      :metadata,
      :retry_count,
      :status,
      :next_retry_at,
      :pushed_at
    ])
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule BackoffDLQTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent
    def start_link(initial \\ 0), do: Agent.start_link(fn -> initial end, name: __MODULE__)
    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      BackoffDLQ.start_link(clock: &Clock.now/0, base_backoff_ms: 1000, max_attempts: 3)

    %{dlq: pid}
  end

  test "push stores a pending, immediately-ready message", %{dlq: dlq} do
    assert {:ok, id} = BackoffDLQ.push(dlq, "q", %{n: 1}, :timeout, %{src: "web"})
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.id == id
    assert e.retry_count == 0
    assert e.status == :pending
    assert e.next_retry_at == 0
    assert [r] = BackoffDLQ.ready(dlq, "q", 10)
    assert r.id == id
  end

  test "peek on unknown queue returns []", %{dlq: dlq} do
    assert BackoffDLQ.peek(dlq, "nope", 10) == []
  end

  test "success removes the message", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :boom, %{})
    assert :ok = BackoffDLQ.retry(dlq, "q", id, fn _ -> :ok end)
    assert BackoffDLQ.peek(dlq, "q", 10) == []
  end

  test "failure bumps retry_count and schedules exponential backoff", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})

    assert {:error, :boom} = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:error, :boom} end)
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
    assert e.next_retry_at == 1000

    Clock.advance(1000)
    assert {:error, :boom} = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:error, :boom} end)
    assert [e2] = BackoffDLQ.peek(dlq, "q", 10)
    assert e2.retry_count == 2
    assert e2.next_retry_at == 3000
  end

  test "retry before next_retry_at is rejected as :not_ready without running the handler", %{
    dlq: dlq
  } do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})
    assert {:error, :boom} = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:error, :boom} end)

    # now still 0, next_retry_at == 1000
    assert {:error, :not_ready, 1000} = BackoffDLQ.retry(dlq, "q", id, fn _ -> :ok end)
    # unchanged retry_count proves the handler did not run
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
  end

  test "ready/3 excludes not-yet-due messages and includes them after the backoff elapses", %{
    dlq: dlq
  } do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})
    assert {:error, :boom} = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:error, :boom} end)

    assert BackoffDLQ.ready(dlq, "q", 10) == []
    Clock.advance(1000)
    assert [r] = BackoffDLQ.ready(dlq, "q", 10)
    assert r.id == id
  end

  test "message becomes :dead after max_attempts failures and cannot be retried", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})

    fail = fn _ -> {:error, :again} end
    # rc 1, due 1000
    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)
    Clock.advance(1000)
    # rc 2, due 3000
    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)
    Clock.advance(2000)
    # rc 3 -> dead
    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)

    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.status == :dead
    assert e.retry_count == 3

    assert {:error, :dead} = BackoffDLQ.retry(dlq, "q", id, fn _ -> :ok end)
    assert BackoffDLQ.ready(dlq, "q", 10) == []
  end

  test "a raising handler counts as failure and does not crash the process", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})
    assert {:error, _} = BackoffDLQ.retry(dlq, "q", id, fn _ -> raise "kaboom" end)
    assert Process.alive?(dlq)
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
  end

  test "retry on unknown id returns :not_found", %{dlq: dlq} do
    assert {:error, :not_found} = BackoffDLQ.retry(dlq, "q", 999, fn _ -> :ok end)
    assert {:error, :not_found} = BackoffDLQ.retry(dlq, "missing", 0, fn _ -> :ok end)
  end

  test "purge removes by age regardless of status", %{dlq: dlq} do
    {:ok, _} = BackoffDLQ.push(dlq, "q", :old, :err, %{})
    Clock.advance(1000)
    {:ok, b} = BackoffDLQ.push(dlq, "q", :new, :err, %{})

    assert {:ok, 1} = BackoffDLQ.purge(dlq, "q", 500)
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.id == b
  end

  test "queues are independent", %{dlq: dlq} do
    {:ok, a} = BackoffDLQ.push(dlq, "a", :ma, :err, %{})
    {:ok, _} = BackoffDLQ.push(dlq, "b", :mb, :err, %{})

    assert {:error, :x} = BackoffDLQ.retry(dlq, "a", a, fn _ -> {:error, :x} end)
    assert [ea] = BackoffDLQ.peek(dlq, "a", 10)
    assert ea.retry_count == 1
    assert [eb] = BackoffDLQ.peek(dlq, "b", 10)
    assert eb.retry_count == 0
  end

  test "a handler returning {:ok, term} is a success that removes the message", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :boom, %{})

    # {:ok, term} is a success: :ok is returned, nothing is left behind, and no
    # retry was counted or backoff scheduled (which a failure classification would do).
    assert :ok = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:ok, :delivered} end)
    assert BackoffDLQ.peek(dlq, "q", 10) == []
    assert BackoffDLQ.ready(dlq, "q", 10) == []
    assert {:error, :not_found} = BackoffDLQ.retry(dlq, "q", id, fn _ -> :ok end)
  end

  test "peek returns at most count entries, oldest-first", %{dlq: dlq} do
    {:ok, a} = BackoffDLQ.push(dlq, "q", :first, :err, %{})
    Clock.advance(10)
    {:ok, b} = BackoffDLQ.push(dlq, "q", :second, :err, %{})
    Clock.advance(10)
    {:ok, c} = BackoffDLQ.push(dlq, "q", :third, :err, %{})

    # count caps the result and the oldest push comes first
    assert [e1, e2] = BackoffDLQ.peek(dlq, "q", 2)
    assert e1.id == a
    assert e1.message == :first
    assert e2.id == b
    assert e2.message == :second

    # a count larger than the queue yields every entry, still oldest-first
    assert Enum.map(BackoffDLQ.peek(dlq, "q", 10), & &1.id) == [a, b, c]
  end

  test "ready returns at most count due entries, oldest-first, skipping not-yet-due ones", %{
    dlq: dlq
  } do
    {:ok, a} = BackoffDLQ.push(dlq, "q", :first, :err, %{})
    Clock.advance(10)
    {:ok, b} = BackoffDLQ.push(dlq, "q", :second, :err, %{})
    Clock.advance(10)
    {:ok, c} = BackoffDLQ.push(dlq, "q", :third, :err, %{})

    # all three are immediately due: count caps the result, oldest-first
    assert Enum.map(BackoffDLQ.ready(dlq, "q", 10), & &1.id) == [a, b, c]
    assert [r1, r2] = BackoffDLQ.ready(dlq, "q", 2)
    assert r1.id == a
    assert r2.id == b

    # failing the oldest pushes it past its backoff, so the next two due entries fill the count
    assert {:error, :boom} = BackoffDLQ.retry(dlq, "q", a, fn _ -> {:error, :boom} end)
    assert Enum.map(BackoffDLQ.ready(dlq, "q", 2), & &1.id) == [b, c]
  end

  test "a handler returning an unrecognised term is a failure that backs off", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})

    assert {:error, _} = BackoffDLQ.retry(dlq, "q", id, fn _ -> :something_else end)
    assert Process.alive?(dlq)

    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.retry_count == 1
    assert e.status == :pending
    assert e.next_retry_at == 1000
    assert BackoffDLQ.ready(dlq, "q", 10) == []
  end

  test "max_attempts defaults to 5 failed retries before the message dies" do
    {:ok, dlq} = BackoffDLQ.start_link(clock: &Clock.now/0)
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})
    fail = fn _ -> {:error, :again} end

    # default backoffs from the default base: 1000, 2000, 4000, 8000
    for advance <- [0, 1000, 2000, 4000] do
      Clock.advance(advance)
      assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)
    end

    # four failures is not yet enough under the default
    assert [e4] = BackoffDLQ.peek(dlq, "q", 10)
    assert e4.retry_count == 4
    assert e4.status == :pending

    Clock.advance(8000)
    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)
    assert [e5] = BackoffDLQ.peek(dlq, "q", 10)
    assert e5.retry_count == 5
    assert e5.status == :dead
    assert {:error, :dead} = BackoffDLQ.retry(dlq, "q", id, fn _ -> :ok end)
  end

  test "base_backoff_ms defaults to 1000 when the option is omitted" do
    {:ok, dlq} = BackoffDLQ.start_link(clock: &Clock.now/0)
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})

    assert {:error, :boom} = BackoffDLQ.retry(dlq, "q", id, fn _ -> {:error, :boom} end)
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.next_retry_at == 1000
    assert BackoffDLQ.ready(dlq, "q", 10) == []

    Clock.advance(999)
    assert {:error, :not_ready, 1} = BackoffDLQ.retry(dlq, "q", id, fn _ -> :ok end)
    Clock.advance(1)
    assert [r] = BackoffDLQ.ready(dlq, "q", 10)
    assert r.id == id
  end

  test "retrying a dead message never invokes the handler", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})
    fail = fn _ -> {:error, :again} end

    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)
    Clock.advance(1000)
    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)
    Clock.advance(2000)
    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)
    assert [dead] = BackoffDLQ.peek(dlq, "q", 10)
    assert dead.status == :dead

    parent = self()
    spy = fn _ -> send(parent, :handler_ran) end

    assert {:error, :dead} = BackoffDLQ.retry(dlq, "q", id, spy)
    refute_receive :handler_ran, 50

    # the dead entry is untouched: no removal, no extra retry counted
    assert [still] = BackoffDLQ.peek(dlq, "q", 10)
    assert still.id == id
    assert still.retry_count == 3
    assert still.status == :dead
  end

  test "purge removes an entry whose age exactly equals older_than", %{dlq: dlq} do
    {:ok, _a} = BackoffDLQ.push(dlq, "q", :exact, :err, %{})
    Clock.advance(400)
    {:ok, b} = BackoffDLQ.push(dlq, "q", :younger, :err, %{})
    Clock.advance(100)

    # a is exactly 500ms old (>= 500 → purged), b is 100ms old (< 500 → kept)
    assert {:ok, 1} = BackoffDLQ.purge(dlq, "q", 500)
    assert [e] = BackoffDLQ.peek(dlq, "q", 10)
    assert e.id == b

    # an unknown queue purges nothing
    assert {:ok, 0} = BackoffDLQ.purge(dlq, "nope", 0)
  end

  test "peek and ready entries carry the error_reason and metadata given at push", %{dlq: dlq} do
    # TODO
  end

  test "a server started with :name registers under that name and serves calls by it" do
    name = :"backoff_dlq_#{System.pid()}_#{System.unique_integer([:positive])}"

    assert {:ok, pid} =
             BackoffDLQ.start_link(
               name: name,
               clock: &Clock.now/0,
               base_backoff_ms: 1000,
               max_attempts: 3
             )

    # the name resolves to the started process
    assert Process.whereis(name) == pid

    # every public call is usable through the registered name
    assert {:ok, id} = BackoffDLQ.push(name, "q", :m, :err, %{src: "web"})
    assert [e] = BackoffDLQ.peek(name, "q", 10)
    assert e.id == id
    assert e.status == :pending
    assert [r] = BackoffDLQ.ready(name, "q", 10)
    assert r.id == id

    # work done via the name is visible via the pid: same process, same state
    assert {:error, :boom} = BackoffDLQ.retry(name, "q", id, fn _ -> {:error, :boom} end)
    assert [e2] = BackoffDLQ.peek(pid, "q", 10)
    assert e2.retry_count == 1
    assert e2.next_retry_at == 1000

    Clock.advance(1000)
    assert :ok = BackoffDLQ.retry(name, "q", id, fn _ -> :ok end)
    assert BackoffDLQ.peek(name, "q", 10) == []
    assert {:ok, 0} = BackoffDLQ.purge(name, "q", 0)
  end
end
```
