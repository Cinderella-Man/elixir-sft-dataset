  @doc """
  Zero all metrics and reply `:ok`.
  """
  @spec reset_metrics(GenServer.server()) :: :ok
  def reset_metrics(server), do: GenServer.call(server, :reset_metrics)