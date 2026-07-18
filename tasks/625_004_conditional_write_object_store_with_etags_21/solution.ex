  @doc """
  Retrieve an object stored under `bucket`/`key`.

  Returns `{:ok, %{data: binary, etag: string, size: integer,
  last_modified: DateTime.t()}}` on success.

  `opts` may contain `{:if_none_match, etag}`: if the object's current ETag
  equals `etag`, `{:error, :not_modified}` is returned instead of the body.

  Returns `{:error, :bucket_not_found}` or `{:error, :not_found}` on failure.
  """
  @spec get_object(GenServer.server(), bucket(), key(), keyword()) ::
          {:ok,
           %{data: binary(), etag: etag(), size: non_neg_integer(), last_modified: DateTime.t()}}
          | {:error, :bucket_not_found | :not_found | :not_modified}
  def get_object(server, bucket, key, opts \\ []) do
    GenServer.call(server, {:get_object, bucket, key, opts})
  end