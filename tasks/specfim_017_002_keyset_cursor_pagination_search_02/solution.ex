  @spec search([product()], map()) ::
          {:ok, page()} | {:error, :invalid_sort_field | :invalid_cursor}