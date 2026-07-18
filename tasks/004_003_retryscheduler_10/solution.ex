  @impl true
  def handle_call({:schedule, name, run_at, mfa, opts}, _from, state) do
    cond do
      Map.has_key?(state.jobs, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        case validate_opts(opts) do
          {:ok, max_attempts, base_delay_ms, backoff_factor} ->
            job = %{
              mfa: mfa,
              status: :pending,
              attempts_so_far: 0,
              next_attempt_at: run_at,
              max_attempts: max_attempts,
              base_delay_ms: base_delay_ms,
              backoff_factor: backoff_factor
            }

            {:reply, :ok, %{state | jobs: Map.put(state.jobs, name, job)}}

          :error ->
            {:reply, {:error, :invalid_opts}, state}
        end
    end
  end

  def handle_call({:cancel, name}, _from, state) do
    case Map.pop(state.jobs, name) do
      {nil, _} -> {:reply, {:error, :not_found}, state}
      {_, new_jobs} -> {:reply, :ok, %{state | jobs: new_jobs}}
    end
  end

  def handle_call({:status, name}, _from, state) do
    case Map.fetch(state.jobs, name) do
      {:ok, job} -> {:reply, {:ok, job.status, job.attempts_so_far}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:jobs, _from, state) do
    list =
      Enum.map(state.jobs, fn {name, j} ->
        {name, j.status, j.next_attempt_at, j.attempts_so_far}
      end)

    {:reply, list, state}
  end