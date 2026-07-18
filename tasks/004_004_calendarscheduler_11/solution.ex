  @impl true
  def handle_info(:tick, state) do
    now = state.clock.()

    new_jobs =
      Enum.reduce(state.jobs, %{}, fn {name, job}, acc ->
        if NaiveDateTime.compare(job.next_run, now) != :gt do
          _ = safe_execute(job.mfa)
          updated = %{job | next_run: compute_next_run(job.rule, now)}
          Map.put(acc, name, updated)
        else
          Map.put(acc, name, job)
        end
      end)

    schedule_tick(state.tick_interval_ms)
    {:noreply, %{state | jobs: new_jobs}}
  end

  def handle_info(_msg, state), do: {:noreply, state}