  @doc """
  Schedules `mfa` to run at `run_at` under `job_name`, retrying with geometric backoff
  per `opts`. Returns `:ok`, `{:error, :already_exists}` when `job_name` is already
  scheduled, or `{:error, :invalid_opts}` when `opts` fail validation.
  """
  def schedule(server, job_name, %NaiveDateTime{} = run_at, {mod, fun, args} = mfa, opts \\ [])
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    GenServer.call(server, {:schedule, job_name, run_at, mfa, opts})
  end