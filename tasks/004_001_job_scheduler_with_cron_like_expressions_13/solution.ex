  defp register_job(name, cron_expr, parsed, mfa, state) do
    now = state.clock.()
    next = next_run_time(parsed, now)

    job = %{
      cron_expression: cron_expr,
      parsed: parsed,
      mfa: mfa,
      next_run: next
    }

    {:reply, :ok, put_in(state, [:jobs, name], job)}
  end