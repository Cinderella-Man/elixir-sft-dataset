  @impl true
  def handle_info(:tick, state) do
    now = state.clock.()

    updated_jobs =
      Map.new(state.jobs, fn {name, job} ->
        if NaiveDateTime.compare(job.next_run, now) != :gt do
          {mod, fun, args} = job.mfa

          try do
            apply(mod, fun, args)
          rescue
            _ -> :ok
          catch
            _, _ -> :ok
          end

          {name, %{job | next_run: next_run_time(job.parsed, now)}}
        else
          {name, job}
        end
      end)

    if state.tick_interval != :infinity do
      Process.send_after(self(), :tick, state.tick_interval)
    end

    {:noreply, %{state | jobs: updated_jobs}}
  end

  # Ignore unexpected messages
  def handle_info(_msg, state), do: {:noreply, state}