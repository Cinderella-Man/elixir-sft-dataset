  @doc """
  Registers a recurring `job_name` that runs `mfa` on `interval_spec`. Returns `:ok`,
  or `{:error, :invalid_interval | :already_exists}`.
  """
  def register(server, job_name, interval_spec, {mod, fun, args} = mfa)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    GenServer.call(server, {:register, job_name, interval_spec, mfa})
  end