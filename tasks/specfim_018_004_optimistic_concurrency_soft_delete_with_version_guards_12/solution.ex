  @spec soft_delete_document(server(), pos_integer(), non_neg_integer()) ::
          {:ok, document()}
          | {:error, :not_found | :already_deleted}
          | {:error, :stale_version, non_neg_integer()}