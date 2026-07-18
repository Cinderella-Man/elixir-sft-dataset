  @doc """
  List the live objects in `bucket`, excluding expired ones, sorted
  lexicographically by key.

  Returns `{:ok, [%{key: string, size: integer, last_modified: DateTime.t()}]}`,
  or `{:error, :bucket_not_found}`.
  """
  @spec list_objects(server(), String.t()) ::
          {:ok, [%{key: String.t(), size: non_neg_integer(), last_modified: DateTime.t()}]}
          | {:error, :bucket_not_found}
  def list_objects(server, bucket) do
    GenServer.call(server, {:list_objects, bucket})
  end