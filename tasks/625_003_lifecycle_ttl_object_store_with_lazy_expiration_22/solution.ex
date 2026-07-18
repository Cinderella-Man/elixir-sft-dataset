  @doc """
  Retrieve the live object stored under `key` in `bucket`.

  Returns `{:ok, %{data: binary, size: integer, last_modified: DateTime.t()}}`,
  `{:error, :bucket_not_found}` if the bucket is missing, or
  `{:error, :not_found}` if the key does not exist or has expired. An expired
  object is removed as part of this call (lazy expiration).
  """
  @spec get_object(server(), String.t(), String.t()) ::
          {:ok, %{data: binary(), size: non_neg_integer(), last_modified: DateTime.t()}}
          | {:error, :bucket_not_found | :not_found}
  def get_object(server, bucket, key) do
    GenServer.call(server, {:get_object, bucket, key})
  end