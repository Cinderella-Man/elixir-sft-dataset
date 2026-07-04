@impl GenServer
def init(%{table_name: table_name}) do
  table =
    :ets.new(table_name, [
      :set,
      :named_table,
      :public,
      read_concurrency: true
    ])

  # Publish both the pid and the table name so the public functions can
  # reach them without a GenServer call, regardless of registration name.
  :persistent_term.put(@pt_server, self())
  :persistent_term.put(@pt_table, table)

  {:ok, %{table: table}}
end