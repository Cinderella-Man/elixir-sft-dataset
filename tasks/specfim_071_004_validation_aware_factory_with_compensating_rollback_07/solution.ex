  @spec insert(factory_name(), overrides()) ::
          {:ok, struct()} | {:error, {:missing_fields, [atom()]}}