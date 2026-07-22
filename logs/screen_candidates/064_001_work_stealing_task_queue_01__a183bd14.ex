defmodule WorkStealQueue do
  @moduledoc """
  Distributes a list of work items across N worker processes using a work-stealing
  algorithm.

  Each worker starts with an evenly-sized slice of the input list held in a shared
  coordinator (an `Agent`). A worker pops items off the front of its own queue and
  applies `process_fn` to them sequentially. When a worker's queue runs dry it looks
  for the busiest worker and steals the back half of that worker's remaining queue.
  When nothing is left to steal anywhere, the worker exits.

  Because pops and steals both go through the coordinator's `Agent.get_and_update/3`,
  each mutation of the shared state is atomic: an item can never be handed to two
  workers. A steal can still lose a race (the victim drained its queue between the
  survey and the steal), in which case the thief simply re-surveys and tries again.

  ## Example

      iex> results = WorkStealQueue.run([1, 2, 3, 4], 2, &(&1 * 10))
      iex> results |> Enum.map(& &1.result) |> Enum.sort()
      [10, 20, 30, 40]

  Only OTP/stdlib is used.
  """

  @typedoc "A single processed item, tagged with the worker that handled it."
  @type result :: %{item: term, result: term, worker_id: non_neg_integer}

  @doc """
  Processes every element of `items` with `process_fn` across `worker_count` workers.

  Blocks until all items have been processed and returns one `t:result/0` map per input
  item, in arbitrary order. `worker_count` may exceed `length(items)`; surplus workers
  simply start with empty queues and either steal or exit immediately.

  Raises `ArgumentError` when `worker_count` is not a positive integer.
  """
  @spec run([term], pos_integer, (term -> term)) :: [result]
  def run(items, worker_count, process_fn)
      when is_list(items) and is_integer(worker_count) and worker_count > 0 and
             is_function(process_fn, 1) do
    case items do
      [] ->
        []

      _ ->
        queues = partition(items, worker_count)
        {:ok, coordinator} = Agent.start_link(fn -> queues end)

        try do
          0..(worker_count - 1)
          |> Enum.map(fn id ->
            Task.async(fn -> work(coordinator, id, process_fn, []) end)
          end)
          |> Task.await_many(:infinity)
          |> Enum.concat()
        after
          Agent.stop(coordinator)
        end
    end
  end

  def run(_items, worker_count, _process_fn) do
    raise ArgumentError, "worker_count must be a positive integer, got: #{inspect(worker_count)}"
  end

  # --- worker loop -------------------------------------------------------------------

  @spec work(Agent.agent(), non_neg_integer, (term -> term), [result]) :: [result]
  defp work(coordinator, id, process_fn, acc) do
    case pop(coordinator, id) do
      {:ok, item} ->
        tagged = %{item: item, result: process_fn.(item), worker_id: id}
        work(coordinator, id, process_fn, [tagged | acc])

      :empty ->
        case steal(coordinator, id) do
          :stole -> work(coordinator, id, process_fn, acc)
          :retry -> work(coordinator, id, process_fn, acc)
          :done -> acc
        end
    end
  end

  # --- coordinator operations --------------------------------------------------------

  # Atomically take the head of this worker's own queue.
  @spec pop(Agent.agent(), non_neg_integer) :: {:ok, term} | :empty
  defp pop(coordinator, id) do
    Agent.get_and_update(coordinator, fn queues ->
      case Map.fetch!(queues, id) do
        [] -> {:empty, queues}
        [item | rest] -> {{:ok, item}, Map.put(queues, id, rest)}
      end
    end)
  end

  # Atomically move the back half of the busiest worker's queue onto this worker's queue.
  #
  # Survey and transfer happen inside a single `get_and_update/3`, so the "busiest"
  # victim cannot drain underneath us. `:retry` is still returned when the busiest queue
  # holds a single item (nothing sensible to split), letting the thief loop around; the
  # `:done` clause guarantees termination once every queue is empty.
  @spec steal(Agent.agent(), non_neg_integer) :: :stole | :retry | :done
  defp steal(coordinator, id) do
    Agent.get_and_update(coordinator, fn queues ->
      {victim, victim_queue} = busiest(queues, id)

      case victim_queue do
        [] ->
          {:done, queues}

        [single] ->
          # Cannot split a single item without leaving the victim idle; hand it over
          # wholesale so the work still moves rather than spinning forever.
          {:stole, queues |> Map.put(victim, []) |> Map.put(id, [single])}

        queue ->
          count = length(queue)
          {keep, taken} = Enum.split(queue, div(count + 1, 2))
          {:stole, queues |> Map.put(victim, keep) |> Map.put(id, taken)}
      end
    end)
  end

  # Returns `{worker_id, queue}` for the worker (other than `id`) with the most work left.
  @spec busiest(%{optional(non_neg_integer) => [term]}, non_neg_integer) ::
          {non_neg_integer, [term]}
  defp busiest(queues, id) do
    queues
    |> Enum.reject(fn {worker_id, _queue} -> worker_id == id end)
    |> Enum.max_by(fn {_worker_id, queue} -> length(queue) end, fn -> {id, []} end)
  end

  # --- partitioning ------------------------------------------------------------------

  # Splits `items` into `worker_count` contiguous chunks whose sizes differ by at most 1.
  @spec partition([term], pos_integer) :: %{optional(non_neg_integer) => [term]}
  defp partition(items, worker_count) do
    total = length(items)
    base = div(total, worker_count)
    extra = rem(total, worker_count)

    {queues, []} =
      Enum.reduce(0..(worker_count - 1), {%{}, items}, fn id, {acc, remaining} ->
        size = base + if id < extra, do: 1, else: 0
        {chunk, rest} = Enum.split(remaining, size)
        {Map.put(acc, id, chunk), rest}
      end)

    queues
  end
end