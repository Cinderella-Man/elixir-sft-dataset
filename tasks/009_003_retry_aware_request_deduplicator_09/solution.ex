  @impl GenServer
  def handle_call({:execute, key, func, retry_config}, from, state) do
    case Map.fetch(state, key) do
      :error ->
        spawn_attempt(key, func)

        entry = %{
          callers: [from],
          func: func,
          retry_config: retry_config,
          attempt: 0,
          status: :running
        }

        {:noreply, Map.put(state, key, entry)}

      {:ok, entry} ->
        updated = %{entry | callers: entry.callers ++ [from]}
        {:noreply, Map.put(state, key, updated)}
    end
  end

  def handle_call({:status, key}, _from, state) do
    reply =
      case Map.fetch(state, key) do
        {:ok, %{attempt: attempt, retry_config: %{max_retries: max}}} when attempt > 0 ->
          {:retrying, attempt, max}

        {:ok, _} ->
          :idle

        :error ->
          :idle
      end

    {:reply, reply, state}
  end