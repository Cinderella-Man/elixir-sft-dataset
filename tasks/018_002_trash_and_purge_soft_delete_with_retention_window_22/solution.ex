  @doc """
  Lists documents sorted by id.

  By default only `:active` documents; pass `include_deleted: true` to
  include trashed and expired documents as well.
  """
  @spec list_documents(GenServer.server(), keyword()) :: [t()]
  def list_documents(server, opts \\ []), do: GenServer.call(server, {:list, opts})