  @spec list_objects(GenServer.server(), bucket()) ::
          {:ok,
           [%{key: key(), etag: etag(), size: non_neg_integer(), last_modified: DateTime.t()}]}
          | {:error, :bucket_not_found}