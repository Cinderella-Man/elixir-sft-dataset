  @spec list_members(server(), term()) ::
          {:ok, [%{user_id: term(), role: role()}]} | {:error, :not_found}