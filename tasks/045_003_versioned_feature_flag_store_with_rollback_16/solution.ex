  @impl true
  def init(%{table_name: table_name}) do
    state_table =
      :ets.new(table_name, [:set, :named_table, :public, read_concurrency: true])

    hist_name = String.to_atom("#{table_name}_history")

    hist_table =
      :ets.new(hist_name, [:ordered_set, :named_table, :public, read_concurrency: true])

    :persistent_term.put(@pt_server, self())
    :persistent_term.put(@pt_state, state_table)
    :persistent_term.put(@pt_hist, hist_table)

    {:ok, %{state_table: state_table, hist_table: hist_table}}
  end