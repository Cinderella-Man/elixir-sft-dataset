  @doc """
  Returns the number of stored intervals that contain `point`.
  """
  @spec stab_count(GenServer.server(), integer()) :: non_neg_integer()
  def stab_count(server, point) when is_integer(point) do
    GenServer.call(server, {:stab_count, point})
  end