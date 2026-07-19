  @spec remove_member_safe(server(), term(), term()) ::
          {:ok, term()} | {:error, :not_found} | {:error, :not_member}