defmodule WorkStealQueue do
  @moduledoc """
  Distributes prioritized work across N worker processes using a work-stealing algorithm.

  Each worker owns a local priority queue (a list sorted by descending priority) and always
  processes its most urgent item next. When a worker drains its own queue it steals from the
  busiest peer, taking the *lowest-priority half* of that peer's queue — the back of the
  victim's sorted list — so the victim keeps grinding on its most urgent work.

  A single `Agent` holds the map of `worker_id => sorted_queue` so that "pop my next item"
  and "slice the tail off the busiest peer" are both atomic operations. Steals that lose a
  race (the victim emptied out first) simply return nothing and the stealing worker retries
  against the new busiest peer, exiting only once no peer has any work left.

  Only OTP/stdlib is used. `run/3` is synchronous and returns one result map per input item.
  """

  @type priority :: integer()
  @type item :: {priority(), term()}
  @type result :: %{
          item: term(),
          priority: priority(),
          result: term(),
          worker_id: non_neg_integer()
        }

  @doc """
  Runs `items` across `worker_count` workers, applying `process_fn` to each payload.

  `items` is a list of `{priority, payload}` tuples where a higher integer priority means
  more urgent. Work is partitioned as evenly as possible, then rebalanced at runtime by
  work stealing. Blocks until every item has been processed.

  Returns a list of `%{item: payload, priority: priority, result: term, worker_id: id}`
  maps — one per input tuple, in unspecified order.

  ## Examples

      iex> results = WorkStealQueue.run([{1, :a}, {5, :b}], 2, &Atom.to_string/1)
      iex> Enum.sort(Enum.map(results, & &1.result))
      ["a", "b"]

      iex> WorkStealQueue.run([], 4, & &1)
      []

      iex> results = WorkStealQueue.run([{9, 2}, {3, 5}], 8, &(&1 * &1))
      iex> Enum.sort(Enum.map(results, &{&1.item, &1.result}))
      [{2, 4}, {5, 25}]
  """
  @spec run([item()], pos_integer(), (term() -> term())) :: [result()]
  def run(items, worker_count, process_fn)
      when is_list(items) and is_integer(worker_count) and worker_count > 0 and
             is_function(process_fn, 1) do
    case items do
      [] ->
        []

      _ ->
        queues = partition(items, worker_count)
        {:ok, agent} = Agent.start_link(fn -> queues end)

        try do
          0..(worker_count - 1)
          |> Enum.map(fn worker_id ->
            Task.async(fn -> work_loop(agent, worker_id, process_fn, []) end)
          end)
          |> Task.await_many(:infinity)
          |> Enum.concat()
        after
          Agent.stop(agent)
        end
    end
  end

  # --- partitioning -------------------------------------------------------------------

  # Deals items round-robin so the split is even to within one item, then sorts each
  # worker's share into descending-priority order.
  @spec partition([item()], pos_integer()) :: %{non_neg_integer() => [item()]}
  defp partition(items, worker_count) do
    empty = Map.new(0..(worker_count - 1), fn id -> {id, []} end)

    items
    |> Enum.with_index()
    |> Enum.reduce(empty, fn {item, index}, acc ->
      Map.update!(acc, rem(index, worker_count), &[item | &1])
    end)
    |> Map.new(fn {id, queue} -> {id, sort_queue(queue)} end)
  end

  @spec sort_queue([item()]) :: [item()]
  defp sort_queue(queue), do: Enum.sort_by(queue, fn {priority, _payload} -> priority end, :desc)

  # --- worker loop --------------------------------------------------------------------

  @spec work_loop(pid(), non_neg_integer(), (term() -> term()), [result()]) :: [result()]
  defp work_loop(agent, worker_id, process_fn, acc) do
    case pop(agent, worker_id) do
      {:ok, {priority, payload}} ->
        result = %{
          item: payload,
          priority: priority,
          result: process_fn.(payload),
          worker_id: worker_id
        }

        work_loop(agent, worker_id, process_fn, [result | acc])

      :empty ->
        case steal(agent, worker_id) do
          :stole -> work_loop(agent, worker_id, process_fn, acc)
          :retry -> work_loop(agent, worker_id, process_fn, acc)
          :done -> acc
        end
    end
  end

  # --- coordination -------------------------------------------------------------------

  @spec pop(pid(), non_neg_integer()) :: {:ok, item()} | :empty
  defp pop(agent, worker_id) do
    Agent.get_and_update(agent, fn queues ->
      case Map.fetch!(queues, worker_id) do
        [] -> {:empty, queues}
        [head | rest] -> {{:ok, head}, Map.put(queues, worker_id, rest)}
      end
    end)
  end

  # Atomically finds the busiest peer and moves the lowest-priority half of its queue onto
  # the thief. `:stole` means work is now waiting locally, `:retry` means the chosen victim
  # was raced to empty, `:done` means no peer has any work left.
  @spec steal(pid(), non_neg_integer()) :: :stole | :retry | :done
  defp steal(agent, worker_id) do
    Agent.get_and_update(agent, fn queues ->
      victim =
        queues
        |> Enum.reject(fn {id, queue} -> id == worker_id or queue == [] end)
        |> Enum.max_by(fn {_id, queue} -> length(queue) end, fn -> nil end)

      case victim do
        nil ->
          {:done, queues}

        {_victim_id, [_only]} ->
          # A lone item is the victim's most urgent work; leave it and re-check.
          {:retry, queues}

        {victim_id, queue} ->
          {kept, stolen} = split_low_half(queue)

          if stolen == [] do
            {:retry, queues}
          else
            queues =
              queues
              |> Map.put(victim_id, kept)
              |> Map.put(worker_id, stolen)

            {:stole, queues}
          end
      end
    end)
  end

  # The queue is sorted descending, so the tail half is the least urgent work.
  @spec split_low_half([item()]) :: {[item()], [item()]}
  defp split_low_half(queue) do
    Enum.split(queue, div(length(queue) + 1, 2))
  end
end