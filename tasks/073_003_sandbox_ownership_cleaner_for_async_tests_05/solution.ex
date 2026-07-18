  @doc "Start or return the running ownership registry. Idempotent."
  @spec ensure_registry() :: {:ok, pid()} | {:error, term()}
  def ensure_registry do
    case Process.whereis(@registry) do
      nil ->
        Agent.start_link(fn -> %{owners: %{}, allow: %{}, shared: nil} end, name: @registry)

      pid ->
        {:ok, pid}
    end
  end