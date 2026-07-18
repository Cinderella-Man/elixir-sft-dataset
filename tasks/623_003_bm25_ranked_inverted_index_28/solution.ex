  @doc """
  Returns index statistics as
  `%{document_count: integer(), term_count: integer()}`.
  """
  @spec stats(GenServer.server()) :: %{document_count: integer(), term_count: integer()}
  def stats(server) do
    GenServer.call(server, :stats)
  end