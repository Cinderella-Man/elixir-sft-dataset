  @spec compile(keyword()) ::
          {:ok, config()}
          | {:error,
             :missing_key_fields
             | :invalid_key_fields
             | :invalid_compare_fields
             | :invalid_rules
             | {:invalid_rule, field()}}