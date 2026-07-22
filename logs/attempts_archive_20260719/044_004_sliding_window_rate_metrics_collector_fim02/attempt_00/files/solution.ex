  @spec prune(non_neg_integer()) :: non_neg_integer()
  def prune(retention_seconds) do
    cutoff = now() - retention_seconds
    :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:"=<", :"$1", cutoff}], [true]}])
  end