  @impl true
  def handle_call({:register, name, spec, mfa}, _from, state) do
    cond do
      Map.has_key?(state.jobs, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        case parse_interval(spec) do
          {:ok, interval_s} ->
            now = state.clock.()

            job = %{
              mfa: mfa,
              interval_spec: spec,
              interval_s: interval_s,
              started_at: now,
              next_run: compute_next_run(now, interval_s, now)
            }

            {:reply, :ok, %{state | jobs: Map.put(state.jobs, name, job)}}

          :error ->
            {:reply, {:error, :invalid_interval}, state}
        end
    end
  end

  def handle_call({:unregister, name}, _from, state) do
    case Map.pop(state.jobs, name) do
      {nil, _} -> {:reply, {:error, :not_found}, state}
      {_, new_jobs} -> {:reply, :ok, %{state | jobs: new_jobs}}
    end
  end

  def handle_call(:jobs, _from, state) do
    list =
      Enum.map(state.jobs, fn {name, job} ->
        {name, job.interval_spec, job.next_run}
      end)

    {:reply, list, state}
  end

  def handle_call({:next_run, name}, _from, state) do
    case Map.fetch(state.jobs, name) do
      {:ok, job} -> {:reply, {:ok, job.next_run}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end