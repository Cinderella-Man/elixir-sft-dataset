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