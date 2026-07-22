defmodule WorkStealQueue do
  @moduledoc """
  A synchronous work-stealing task distributor with steal instrumentation.

  `run/4` partitions a list of items across `worker_count` `Task` workers. Each worker owns a
  local queue, held in a shared `Agent` so that idle workers can atomically locate the busiest
  peer and steal a contiguous batch off the *back* of that peer's queue.

  Alongside the per-item results, `run/4` reports how much stealing actually happened: the
  number of successful steal operations per worker, the number of items each worker stole, and
  the number of items each worker ultimately processed.

  ## Example

      iex> out = WorkStealQueue.run(Enum.to_list(1..10), 2, &(&1 * 2))
      iex> Enum.sort(Enum.map(out.results, & &1.result))
      [2, 4, 6, 8, 10, 12, 14, 16, 18, 20]
      iex> Map.keys(out.metrics.processed) |> Enum.sort()
      [0, 1]

  ## Options

    * `:steal_batch` - `:half` (default) steals half of the victim's remaining queue, rounded
      down but never fewer than one item, so a non-empty queue is always stealable. A positive
      integer `n` steals up to `n` items per steal operation.
  """

  @typedoc "Zero-based worker identifier."
  @type worker_id :: non_neg_integer

  @typedoc "A single processed item, tagged with the worker that ran it."
  @type result_entry :: %{item: term, result: term, worker_id: worker_id}

  @typedoc "Steal instrumentation, keyed by worker id."
  @type metrics :: %{
          processed: %{worker_id => non_neg_integer},
          steals: %{worker_id => non_neg_integer},
          stolen: %{worker_id => non_neg_integer}
        }

  @typedoc "Return value of `run/4`."
  @type run_result :: %{results: [result_entry], metrics: metrics}

  @typedoc "Supported `:steal_batch` values."
  @type steal_batch :: :half | pos_integer

  @doc """
  Processes `items` across `worker_count` work-stealing workers using `process_fn`.

  Blocks until every item has been processed. Returns a map with a `:results` list (exactly one
  entry per input item, each tagged with the `:worker_id` that processed it) and a `:metrics`
  map whose `:processed`, `:steals` and `:stolen` sub-maps contain an entry for every worker id
  in `0..worker_count - 1`, defaulting to `0`.

  Supported options are described in the module documentation.

  ## Examples

      iex> out = WorkStealQueue.run([1, 2, 3], 4, &(&1 + 1), steal_batch: 1)
      iex> Enum.sort(Enum.map(out.results, & &1.result))
      [2, 3, 4]
      iex> map_size(out.metrics.steals)
      4
  """
  @spec run([term], pos_integer, (term -> term), keyword) :: run_result
  def run(items, worker_count, process_fn, opts \\ [])
      when is_list(items) and is_integer(worker_count) and worker_count > 0 and
             is_function(process_fn, 1) and is_list(opts) do
    batch = validate_batch(Keyword.get(opts, :steal_batch, :half))
    ids = Enum.to_list(0..(worker_count - 1))
    queues = ids |> Enum.zip(partition(items, worker_count)) |> Map.new()

    {:ok, agent} = Agent.start_link(fn -> queues end)

    try do
      ids
      |> Enum.map(fn id -> Task.async(fn -> work(id, agent, process_fn, batch) end) end)
      |> Enum.map(&Task.await(&1, :infinity))
      |> assemble(ids)
    after
      Agent.stop(agent)
    end
  end

  # -- worker loop -------------------------------------------------------------------------

  @spec work(worker_id, pid, (term -> term), steal_batch) :: map
  defp work(id, agent, process_fn, batch) do
    state = %{worker_id: id, results: [], processed: 0, steals: 0, stolen: 0}
    state = drain(id, agent, process_fn, state)
    loop(id, agent, process_fn, batch, state)
  end

  @spec loop(worker_id, pid, (term -> term), steal_batch, map) :: map
  defp loop(id, agent, process_fn, batch, state) do
    case steal(agent, id, batch) do
      [] ->
        %{state | results: Enum.reverse(state.results)}

      items ->
        state = %{state | steals: state.steals + 1, stolen: state.stolen + length(items)}
        state = Enum.reduce(items, state, &process(&1, &2, id, process_fn))
        loop(id, agent, process_fn, batch, state)
    end
  end

  # Processes the worker's own queue one item at a time, so peers can steal the tail meanwhile.
  @spec drain(worker_id, pid, (term -> term), map) :: map
  defp drain(id, agent, process_fn, state) do
    case take_own(agent, id) do
      :empty -> state
      {:ok, item} -> drain(id, agent, process_fn, process(item, state, id, process_fn))
    end
  end

  @spec process(term, map, worker_id, (term -> term)) :: map
  defp process(item, state, id, process_fn) do
    entry = %{item: item, result: process_fn.(item), worker_id: id}
    %{state | results: [entry | state.results], processed: state.processed + 1}
  end

  # -- shared queue operations -------------------------------------------------------------

  @spec take_own(pid, worker_id) :: {:ok, term} | :empty
  defp take_own(agent, id) do
    Agent.get_and_update(agent, fn queues ->
      case Map.fetch!(queues, id) do
        [] -> {:empty, queues}
        [item | rest] -> {{:ok, item}, Map.put(queues, id, rest)}
      end
    end)
  end

  # Atomically finds the busiest peer and removes a batch from the back of its queue.
  @spec steal(pid, worker_id, steal_batch) :: [term]
  defp steal(agent, id, batch) do
    Agent.get_and_update(agent, fn queues ->
      victim =
        queues
        |> Enum.reject(fn {vid, queue} -> vid == id or queue == [] end)
        |> Enum.max_by(fn {_vid, queue} -> length(queue) end, fn -> nil end)

      case victim do
        nil ->
          {[], queues}

        {vid, queue} ->
          size = length(queue)
          take = min(size, batch_size(batch, size))
          {kept, stolen} = Enum.split(queue, size - take)
          {stolen, Map.put(queues, vid, kept)}
      end
    end)
  end

  @spec batch_size(steal_batch, pos_integer) :: pos_integer
  defp batch_size(:half, size), do: max(div(size, 2), 1)
  defp batch_size(n, _size) when is_integer(n), do: n

  # -- helpers -----------------------------------------------------------------------------

  @spec validate_batch(term) :: steal_batch
  defp validate_batch(:half), do: :half
  defp validate_batch(n) when is_integer(n) and n > 0, do: n

  defp validate_batch(other) do
    raise ArgumentError, ":steal_batch must be :half or a positive integer, got: #{inspect(other)}"
  end

  # Splits `items` into `count` chunks whose sizes differ by at most one.
  @spec partition([term], pos_integer) :: [[term]]
  defp partition(items, count) do
    total = length(items)
    base = div(total, count)
    extra = rem(total, count)

    {chunks, []} =
      Enum.map_reduce(0..(count - 1), items, fn index, rest ->
        size = if index < extra, do: base + 1, else: base
        Enum.split(rest, size)
      end)

    chunks
  end

  @spec assemble([map], [worker_id]) :: run_result
  defp assemble(states, ids) do
    zeros = Map.new(ids, &{&1, 0})

    metrics =
      Enum.reduce(states, %{processed: zeros, steals: zeros, stolen: zeros}, fn state, acc ->
        %{
          processed: Map.put(acc.processed, state.worker_id, state.processed),
          steals: Map.put(acc.steals, state.worker_id, state.steals),
          stolen: Map.put(acc.stolen, state.worker_id, state.stolen)
        }
      end)

    %{results: Enum.flat_map(states, & &1.results), metrics: metrics}
  end
end