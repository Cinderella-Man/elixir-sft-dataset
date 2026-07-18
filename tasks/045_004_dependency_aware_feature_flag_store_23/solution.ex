  @doc """
  Declares that `flag` requires every flag in `prereqs`.

  Returns `{:error, :cycle}` (leaving the graph unchanged) if the edges would
  create a cycle — including self-dependency or a transitive loop — otherwise
  `:ok`. The flag's own state is preserved.
  """
  @spec set_prerequisites(atom(), [atom()]) :: :ok | {:error, :cycle}
  def set_prerequisites(flag, prereqs) when is_list(prereqs) do
    GenServer.call(server(), {:set_prereqs, flag, prereqs})
  end