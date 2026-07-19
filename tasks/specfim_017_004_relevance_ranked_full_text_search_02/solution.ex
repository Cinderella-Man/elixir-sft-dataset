  @spec search([product()], map()) ::
          {:ok, %{data: [result_item()]}} | {:error, :invalid_sort_field}