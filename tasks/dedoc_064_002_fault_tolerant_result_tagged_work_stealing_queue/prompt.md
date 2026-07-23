# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule WorkStealQueue do
  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def run(items, worker_count, process_fn)
      when is_list(items) and is_integer(worker_count) and worker_count > 0 and
             is_function(process_fn, 1) do
    partitions = partition(items, worker_count)

    {:ok, coordinator} =
      Agent.start_link(fn ->
        partitions
        |> Enum.with_index()
        |> Map.new(fn {queue, id} -> {id, queue} end)
      end)

    results =
      0..(worker_count - 1)
      |> Enum.map(fn id ->
        Task.async(fn -> run_worker(id, coordinator, process_fn) end)
      end)
      |> Task.await_many(:infinity)
      |> List.flatten()

    Agent.stop(coordinator)
    results
  end

  # ---------------------------------------------------------------------------
  # Worker logic
  # ---------------------------------------------------------------------------

  defp run_worker(id, coordinator, process_fn) do
    process_local_queue(id, coordinator, process_fn, [])
  end

  defp process_local_queue(id, coordinator, process_fn, acc) do
    case pop_item(id, coordinator) do
      {:ok, item} ->
        result = safe_apply(process_fn, item)
        entry = %{item: item, result: result, worker_id: id}
        process_local_queue(id, coordinator, process_fn, [entry | acc])

      :empty ->
        try_steal(id, coordinator, process_fn, acc)
    end
  end

  # Wrap a single item's processing so raise/throw/exit become tagged results.
  defp safe_apply(process_fn, item) do
    try do
      {:ok, process_fn.(item)}
    rescue
      e -> {:error, %{kind: :error, reason: Exception.message(e)}}
    catch
      :throw, value -> {:error, %{kind: :throw, reason: value}}
      :exit, reason -> {:error, %{kind: :exit, reason: reason}}
    end
  end

  defp try_steal(id, coordinator, process_fn, acc) do
    case find_victim(id, coordinator) do
      nil ->
        acc

      victim_id ->
        case steal_half(victim_id, coordinator) do
          [] ->
            try_steal(id, coordinator, process_fn, acc)

          stolen ->
            Agent.update(coordinator, fn state ->
              Map.update(state, id, stolen, fn existing -> stolen ++ existing end)
            end)

            process_local_queue(id, coordinator, process_fn, acc)
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Coordinator operations
  # ---------------------------------------------------------------------------

  defp pop_item(id, coordinator) do
    Agent.get_and_update(coordinator, fn state ->
      case Map.fetch!(state, id) do
        [] -> {:empty, state}
        [head | tail] -> {{:ok, head}, Map.put(state, id, tail)}
      end
    end)
  end

  defp find_victim(thief_id, coordinator) do
    Agent.get(coordinator, fn state ->
      state
      |> Enum.reject(fn {id, queue} -> id == thief_id or queue == [] end)
      |> case do
        [] ->
          nil

        candidates ->
          {victim_id, _queue} = Enum.max_by(candidates, fn {_id, q} -> length(q) end)
          victim_id
      end
    end)
  end

  defp steal_half(victim_id, coordinator) do
    Agent.get_and_update(coordinator, fn state ->
      queue = Map.fetch!(state, victim_id)
      len = length(queue)

      if len < 2 do
        {[], state}
      else
        steal_count = div(len, 2)
        keep_count = len - steal_count
        {keep, stolen} = Enum.split(queue, keep_count)
        {stolen, Map.put(state, victim_id, keep)}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Partitioning
  # ---------------------------------------------------------------------------

  defp partition(items, n) do
    total = length(items)
    base_size = div(total, n)
    extras = rem(total, n)

    {chunks, _remaining} =
      Enum.reduce(0..(n - 1), {[], items}, fn i, {acc, rest} ->
        chunk_size = if i < extras, do: base_size + 1, else: base_size
        {chunk, tail} = Enum.split(rest, chunk_size)
        {[chunk | acc], tail}
      end)

    Enum.reverse(chunks)
  end
end
```
