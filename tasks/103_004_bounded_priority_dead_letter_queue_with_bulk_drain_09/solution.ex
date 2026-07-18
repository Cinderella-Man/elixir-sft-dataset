  @impl true
  def handle_call({:push, queue, message, error_reason, metadata, priority}, _from, state) do
    entries = Map.get(state.queues, queue, [])

    if full?(state.capacity, length(entries)) do
      {:reply, {:error, :full}, state}
    else
      id = state.next_id

      entry = %{
        id: id,
        message: message,
        error_reason: error_reason,
        metadata: metadata,
        priority: priority,
        retry_count: 0,
        pushed_at: state.clock.()
      }

      state = put_queue(%{state | next_id: id + 1}, queue, entries ++ [entry])
      {:reply, {:ok, id}, state}
    end
  end

  def handle_call({:peek, queue, count}, _from, state) do
    entries =
      state.queues
      |> Map.get(queue, [])
      |> ordered()
      |> Enum.take(count)
      |> Enum.map(&public/1)

    {:reply, entries, state}
  end

  def handle_call({:drain, queue, handler, count}, _from, state) do
    entries = Map.get(state.queues, queue, [])
    to_visit = entries |> ordered() |> Enum.take(count)

    {outcomes, stats} =
      Enum.reduce(to_visit, {%{}, %{succeeded: 0, failed: 0, processed: []}}, fn
        entry, {out, acc} ->
          acc = %{acc | processed: acc.processed ++ [entry.id]}

          case run_handler(handler, entry.message) do
            :success ->
              {Map.put(out, entry.id, :remove), %{acc | succeeded: acc.succeeded + 1}}

            {:failure, _reason} ->
              {Map.put(out, entry.id, {:keep, entry.retry_count + 1}),
               %{acc | failed: acc.failed + 1}}
          end
      end)

    new_entries =
      entries
      |> Enum.reduce([], fn e, acc ->
        case Map.get(outcomes, e.id) do
          :remove -> acc
          {:keep, rc} -> [%{e | retry_count: rc} | acc]
          nil -> [e | acc]
        end
      end)
      |> Enum.reverse()

    {:reply, {:ok, stats}, put_queue(state, queue, new_entries)}
  end

  def handle_call({:purge, queue, older_than}, _from, state) do
    entries = Map.get(state.queues, queue, [])
    now = state.clock.()
    {kept, purged} = Enum.split_with(entries, fn e -> now - e.pushed_at < older_than end)
    {:reply, {:ok, length(purged)}, put_queue(state, queue, kept)}
  end