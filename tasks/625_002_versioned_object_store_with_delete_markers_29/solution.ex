  @doc """
  Return `{:ok, buckets}` where `buckets` is a sorted list of bucket names.
  """
  @spec list_buckets(server()) :: {:ok, [String.t()]}
  def list_buckets(server) do
    GenServer.call(server, :list_buckets)
  end