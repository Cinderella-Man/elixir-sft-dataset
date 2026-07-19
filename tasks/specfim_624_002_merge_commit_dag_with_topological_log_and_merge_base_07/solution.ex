  @spec merge_base(server(), hash(), hash()) ::
          {:ok, hash()} | {:error, :not_found | :no_merge_base}