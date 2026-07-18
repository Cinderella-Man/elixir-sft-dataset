  @doc """
  Returns the total number of distinct series stored across all shards.
  """
  @spec series_count(server()) :: non_neg_integer()
  def series_count(server) do
    GenServer.call(server, :series_count)
  end