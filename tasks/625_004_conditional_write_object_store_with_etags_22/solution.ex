  @doc """
  List the objects in `bucket`, sorted lexicographically by key.

  Each entry is `%{key: string, etag: string, size: integer,
  last_modified: DateTime.t()}`. Returns `{:error, :bucket_not_found}` when
  the bucket does not exist.
  """
  @spec list_objects(GenServer.server(), bucket()) ::
          {:ok,
           [%{key: key(), etag: etag(), size: non_neg_integer(), last_modified: DateTime.t()}]}
          | {:error, :bucket_not_found}
  def list_objects(server, bucket) do
    GenServer.call(server, {:list_objects, bucket})
  end