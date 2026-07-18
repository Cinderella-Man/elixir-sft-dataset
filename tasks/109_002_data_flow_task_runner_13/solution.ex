  @spec run_all(GenServer.server()) ::
          {:ok, map()}
          | {:error, {:cycle, [term()]}}
          | {:error, {:unknown_dependencies, [term()]}}
  @doc """
  Validates the dependency graph and executes every submitted task.

  Returns `{:ok, results}` on success, `{:error, {:cycle, involved}}` when the
  graph contains a cycle, or `{:error, {:unknown_dependencies, missing}}` when a
  task references a dependency that was never submitted. In both error cases no
  task is executed.
  """
  def run_all(name) do
    GenServer.call(name, :run_all, :infinity)
  end