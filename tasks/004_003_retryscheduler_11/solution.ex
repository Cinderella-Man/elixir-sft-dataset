  @impl true
  def handle_info(:tick, state) do
    now = state.clock.()

    new_jobs =
      Enum.reduce(state.jobs, %{}, fn {name, job}, acc ->
        updated =
          if job.status == :pending and NaiveDateTime.compare(job.next_attempt_at, now) != :gt do
            process_attempt(job, now)
          else
            job
          end

        Map.put(acc, name, updated)
      end)

    schedule_tick(state.tick_interval_ms)
    {:noreply, %{state | jobs: new_jobs}}
  end

  def handle_info(_msg, state), do: {:noreply, state}