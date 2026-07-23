# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule ConcurrentPriorityQueue do
  use GenServer

  @priority_order [:critical, :normal, :low]

  # Unique marker used to distinguish "no result was reported" from a legitimate `nil` result.
  @no_result :"$concurrent_priority_queue_no_result"

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {processor, opts} = Keyword.pop(opts, :processor, fn task -> task end)
    {max_concurrency, opts} = Keyword.pop(opts, :max_concurrency, 1)
    {name, _opts} = Keyword.pop(opts, :name)

    if not (is_integer(max_concurrency) and max_concurrency > 0) do
      raise ArgumentError, ":max_concurrency must be a positive integer"
    end

    gen_opts = if name, do: [name: name], else: []

    GenServer.start_link(
      __MODULE__,
      %{processor: processor, max_concurrency: max_concurrency},
      gen_opts
    )
  end

  def enqueue(server, task, priority) when priority in @priority_order do
    GenServer.call(server, {:enqueue, task, priority})
  end

  def status(server) do
    GenServer.call(server, :status)
  end

  def processed(server) do
    GenServer.call(server, :processed)
  end

  def drain(server) do
    GenServer.call(server, :drain, :infinity)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{processor: processor, max_concurrency: max_concurrency}) do
    state = %{
      queues: %{critical: :queue.new(), normal: :queue.new(), low: :queue.new()},
      processor: processor,
      max_concurrency: max_concurrency,
      # Map of pid => {task, monitor_ref}
      active_workers: %{},
      # Map of pid => result (received before :DOWN)
      pending_results: %{},
      processed: [],
      drain_waiters: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, task, priority}, _from, state) do
    updated_queue = :queue.in(task, state.queues[priority])
    queues = Map.put(state.queues, priority, updated_queue)

    state =
      %{state | queues: queues}
      |> maybe_trigger_processing()

    {:reply, :ok, state}
  end

  def handle_call(:status, _from, state) do
    counts = %{
      critical: :queue.len(state.queues.critical),
      normal: :queue.len(state.queues.normal),
      low: :queue.len(state.queues.low),
      active: map_size(state.active_workers),
      max_concurrency: state.max_concurrency
    }

    {:reply, counts, state}
  end

  def handle_call(:processed, _from, state) do
    {:reply, Enum.reverse(state.processed), state}
  end

  def handle_call(:drain, from, state) do
    if queue_empty?(state) and map_size(state.active_workers) == 0 do
      {:reply, :ok, state}
    else
      {:noreply, %{state | drain_waiters: [from | state.drain_waiters]}}
    end
  end

  @impl true
  def handle_info(:process_next, state) do
    if map_size(state.active_workers) >= state.max_concurrency do
      # All slots full — processing is re-triggered when a worker finishes.
      {:noreply, state}
    else
      case pop_highest(state.queues) do
        {nil, _queues} ->
          {:noreply, maybe_notify_drain(state)}

        {task, queues} ->
          parent = self()
          processor = state.processor

          {pid, ref} =
            spawn_monitor(fn ->
              result = processor.(task)
              send(parent, {:task_result, self(), result})
            end)

          active_workers = Map.put(state.active_workers, pid, {task, ref})

          new_state =
            %{state | queues: queues, active_workers: active_workers}
            |> maybe_trigger_processing()

          {:noreply, new_state}
      end
    end
  end

  def handle_info({:task_result, pid, result}, state) do
    if Map.has_key?(state.active_workers, pid) do
      # Store the result; it is finalized when the worker's :DOWN arrives.
      {:noreply, %{state | pending_results: Map.put(state.pending_results, pid, result)}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.pop(state.active_workers, pid) do
      {{task, ^ref}, remaining_workers} ->
        {result, pending_results} = Map.pop(state.pending_results, pid, @no_result)

        processed =
          case result do
            @no_result -> state.processed
            value -> [{task, value} | state.processed]
          end

        state =
          %{
            state
            | active_workers: remaining_workers,
              pending_results: pending_results,
              processed: processed
          }
          |> maybe_trigger_processing()
          |> maybe_notify_drain()

        {:noreply, state}

      {_other, _workers} ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp maybe_trigger_processing(state) do
    available_slots = state.max_concurrency - map_size(state.active_workers)

    if available_slots > 0 and not queue_empty?(state) do
      send(self(), :process_next)
    end

    state
  end

  defp pop_highest(queues) do
    Enum.find_value(@priority_order, {nil, queues}, fn priority ->
      case :queue.out(queues[priority]) do
        {{:value, task}, rest} -> {task, Map.put(queues, priority, rest)}
        {:empty, _} -> nil
      end
    end)
  end

  defp queue_empty?(state) do
    Enum.all?(@priority_order, fn p -> :queue.is_empty(state.queues[p]) end)
  end

  defp maybe_notify_drain(state) do
    if queue_empty?(state) and map_size(state.active_workers) == 0 do
      notify_drain_waiters(state)
    else
      state
    end
  end

  defp notify_drain_waiters(%{drain_waiters: []} = state), do: state

  defp notify_drain_waiters(state) do
    Enum.each(state.drain_waiters, &GenServer.reply(&1, :ok))
    %{state | drain_waiters: []}
  end
end
```
