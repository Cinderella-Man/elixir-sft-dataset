  # Classify one array element. Guards keep the never-raise promise: a
  # non-object element has no type field at all (:missing_type), and an
  # unroutable discriminator may be ANY JSON value — inspect/1 it, string
  # interpolation would raise on maps and lists.
  @spec classify(term(), String.t(), routing()) :: {:ok, schema()} | :missing_type | :unroutable
  defp classify(record, type_field, routing) when is_map(record) do
    case Map.fetch(record, type_field) do
      :error ->
        Logger.warning("[Ingestion] record missing '#{type_field}', skipping")
        :missing_type

      {:ok, type_value} ->
        case Map.fetch(routing, type_value) do
          :error ->
            Logger.warning("[MultiSchemaIngestion] Unknown type #{inspect(type_value)}, skipping")
            :unroutable

          {:ok, schema} ->
            {:ok, schema}
        end
    end
  end

  defp classify(record, type_field, _routing) do
    Logger.warning(
      "[Ingestion] non-object record #{inspect(record, limit: 3)} " <>
        "has no '#{type_field}', skipping"
    )

    :missing_type
  end