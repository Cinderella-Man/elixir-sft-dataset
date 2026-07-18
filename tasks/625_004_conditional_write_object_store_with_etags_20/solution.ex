  @doc """
  List all bucket names, sorted lexicographically.
  """
  @spec list_buckets(GenServer.server()) :: {:ok, [bucket()]}
  def list_buckets(server) do
    GenServer.call(server, :list_buckets)
  end