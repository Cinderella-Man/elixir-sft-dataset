  @impl true
  def handle_call({:push, queue, key, message, error_reason, metadata}, _from, state) do
    entries = Map.get(state.queues, queue, [])
    now = state.clock.()

    case Enum.find(entries, &(&1.dedup_key == key)) do
      nil ->
        id = state.next_id

        entry = %{
          id: id,
          dedup_key: key,
          message: message,
          error_reason: error_reason,
          metadata: metadata,
          occurrences: 1,
          retry_count: 0,
          first_seen: now,
          last_seen: now
        }

        state = put_queue(%{state | next_id: id + 1}, queue, entries ++ [entry])
        {:reply, {:ok, :new, id}, state}

      existing ->
        updated = %{
          existing
          | occurrences: existing.occurrences + 1,
            last_seen: now,
            message: message,
            error_reason: error_reason,
            metadata: metadata
        }

        new = Enum.map(entries, fn e -> if e.dedup_key == key, do: updated, else: e end)
        {:reply, {:ok, :duplicate, existing.id}, put_queue(state, queue, new)}
    end
  end

  def handle_call({:peek, queue, count}, _from, state) do
    entries = state.queues |> Map.get(queue, []) |> Enum.take(count) |> Enum.map(&public/1)
    {:reply, entries, state}
  end

  def handle_call({:retry, queue, key, handler}, _from, state) do
    entries = Map.get(state.queues, queue, [])

    case Enum.find(entries, &(&1.dedup_key == key)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      entry ->
        case run_handler(handler, entry.message) do
          :success ->
            new = Enum.reject(entries, &(&1.dedup_key == key))
            {:reply, :ok, put_queue(state, queue, new)}

          {:failure, reason} ->
            new =
              Enum.map(entries, fn
                %{dedup_key: ^key} = e -> %{e | retry_count: e.retry_count + 1}
                e -> e
              end)

            {:reply, {:error, reason}, put_queue(state, queue, new)}
        end
    end
  end

  def handle_call({:purge, queue, older_than}, _from, state) do
    entries = Map.get(state.queues, queue, [])
    now = state.clock.()
    {kept, purged} = Enum.split_with(entries, fn e -> now - e.last_seen < older_than end)
    {:reply, {:ok, length(purged)}, put_queue(state, queue, kept)}
  end