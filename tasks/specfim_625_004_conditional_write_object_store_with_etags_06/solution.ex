  @spec get_object(GenServer.server(), bucket(), key(), keyword()) ::
          {:ok,
           %{data: binary(), etag: etag(), size: non_neg_integer(), last_modified: DateTime.t()}}