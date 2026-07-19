  @spec add_member_safe(server(), term(), term(), role()) ::
          {:ok, term()} | {:error, :not_found} | {:error, :conflict}