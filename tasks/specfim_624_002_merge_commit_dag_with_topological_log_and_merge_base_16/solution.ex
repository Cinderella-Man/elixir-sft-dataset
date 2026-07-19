  @spec do_merge_base(map(), hash(), hash()) ::
          {:ok, hash()} | {:error, :not_found | :no_merge_base}