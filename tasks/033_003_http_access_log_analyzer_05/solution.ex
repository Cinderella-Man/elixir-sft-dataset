  @doc "Analyzes the HTTP access log at `path`. Returns `{:ok, stats}` or `{:error, reason}`."
  @spec analyze(String.t()) :: {:ok, map()} | {:error, term()}
  def analyze(path) do
    with {:ok, :regular} <- check_readable(path) do
      stream_report(path)
    end
  end