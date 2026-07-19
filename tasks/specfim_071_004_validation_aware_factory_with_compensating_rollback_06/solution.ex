  @spec insert(factory_name()) ::
          {:ok, struct()} | {:error, {:missing_fields, [atom()]}}