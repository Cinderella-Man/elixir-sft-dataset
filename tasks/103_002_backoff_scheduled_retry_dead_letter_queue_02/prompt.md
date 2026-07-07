# Implement `handle_call/3` for `BackoffDLQ`

Implement the GenServer `handle_call/3` callback. It has one clause per public
operation; each clause receives the tagged request tuple, the `_from` reference,
and the current `state`, and must return a `{:reply, reply, new_state}` tuple.
The `state` map holds `:clock` (a zero-arity function returning the current time
in ms), `:base` (base backoff in ms), `:max_attempts`, `:next_id`, and `:queues`
(a map of `queue_name => list_of_entries`, kept oldest-first). Use the provided
helpers `public/1`, `run_handler/2`, `pow2/1`, and `put_queue/3`.

Handle each request as follows:

- `{:push, queue, message, error_reason, metadata}` — take the current `next_id`
  as the new entry's `id` and read `now` from the clock. Build an entry map with
  `id`, `message`, `error_reason`, `metadata`, `retry_count: 0`, `status: :pending`,
  `pushed_at: now`, and `next_retry_at: now` (immediately eligible). Append it to
  the end of that queue's list (creating the queue if absent). Reply `{:ok, id}`
  and bump `next_id`.

- `{:peek, queue, count}` — return up to `count` entries from the queue,
  oldest-first, unchanged, each mapped through `public/1`. Unknown/empty queue
  returns `[]`. State is unchanged.

- `{:ready, queue, count}` — read `now`, then return up to `count` entries,
  oldest-first, that are currently retryable — status `:pending` **and**
  `now >= next_retry_at` — each mapped through `public/1`. State is unchanged.

- `{:retry, queue, id, handler}` — find the entry by `id` in the queue.
  - Missing → reply `{:error, :not_found}`.
  - Status `:dead` → reply `{:error, :dead}` (do not invoke the handler).
  - Otherwise read `now`; if `now < next_retry_at`, reply
    `{:error, :not_ready, next_retry_at - now}` (do not invoke the handler).
  - Otherwise run the handler via `run_handler/2`. On `:success`, remove the
    entry and reply `:ok`. On `{:failure, reason}`, increment `retry_count`; if
    the new count `>= max_attempts` mark the entry `:dead`, otherwise set
    `next_retry_at` to `now + base * pow2(retry_count - 1)`. Keep the entry
    (updated in place) and reply `{:error, reason}`.

- `{:purge, queue, older_than}` — read `now`, keep only entries whose age
  `now - pushed_at < older_than` (regardless of status), and reply
  `{:ok, purged_count}` with the state updated to the kept entries.

Use `put_queue/3` to write back a queue's entry list (it deletes empty queues).

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

  def handle_call({:push, queue, message, error_reason, metadata}, _from, state) do
    # TODO
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
    Map.take(e, [:id, :message, :error_reason, :metadata, :retry_count, :status,
                 :next_retry_at, :pushed_at])
  end
end
```