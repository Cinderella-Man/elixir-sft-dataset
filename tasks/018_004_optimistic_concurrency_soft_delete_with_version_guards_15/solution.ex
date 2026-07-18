  @doc """
  Lists documents sorted by id.

  Active documents only by default; pass `include_deleted: true` for all.
  """
  @spec list_documents(server(), keyword()) :: [document()]
  def list_documents(s, opts \\ []), do: GenServer.call(s, {:list, opts})