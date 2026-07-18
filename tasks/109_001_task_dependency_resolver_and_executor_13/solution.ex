  @doc """
  Validates the dependency graph and executes all submitted tasks.

  Returns `{:ok, results}` on success, where `results` maps each `task_id` to
  the value returned by its `:func`.

  Returns `{:error, {:unknown_dependencies, missing}}` if any task depends on a
  `task_id` that was never submitted, and `{:error, {:cycle, involved}}` if the
  graph contains a cycle. In both error cases no task is executed.
  """
  def run_all(name) do
    GenServer.call(name, :run_all, :infinity)
  end