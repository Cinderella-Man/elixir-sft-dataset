  @doc "Return `%{document_count: integer, term_count: integer}`."
  def stats(server) do
    GenServer.call(server, :stats)
  end