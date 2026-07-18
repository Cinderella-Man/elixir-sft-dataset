  @impl true
  def init(%{table_name: table_name}) do
    table =
      :ets.new(table_name, [:set, :named_table, :public, read_concurrency: true])

    :persistent_term.put(@pt_server, self())
    :persistent_term.put(@pt_table, table)
    {:ok, %{table: table}}
  end