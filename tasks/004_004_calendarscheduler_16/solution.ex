  def register(server, job_name, rule, {mod, fun, args} = mfa)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    GenServer.call(server, {:register, job_name, rule, mfa})
  end