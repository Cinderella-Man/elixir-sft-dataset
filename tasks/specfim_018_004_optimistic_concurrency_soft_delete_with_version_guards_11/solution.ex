  @spec update_document(server(), pos_integer(), attrs(), non_neg_integer()) ::
          {:ok, document()}
          | {:error, :not_found}
          | {:error, :stale_version, non_neg_integer()}
          | {:error, errors()}