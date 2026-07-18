  @spec decode_history_row(map()) :: map()
  defp decode_history_row(row) do
    %{
      event: String.to_existing_atom(row.event),
      from_state: String.to_existing_atom(row.from_state),
      to_state: String.to_existing_atom(row.to_state),
      inserted_at: row.inserted_at
    }
  end