  @spec restore_document(server(), pos_integer(), non_neg_integer()) ::
          {:ok, document()}
          | {:error, :not_found | :not_deleted}
          | {:error, :stale_version, non_neg_integer()}