  @doc """
  Drains and returns the buffered matched entries, in pair-completion order.

  The buffer is emptied, so an immediately following call returns `[]`.
  """
  @spec take_matches(GenServer.server()) :: [entry()]
  def take_matches(server) do
    GenServer.call(server, :take_matches)
  end