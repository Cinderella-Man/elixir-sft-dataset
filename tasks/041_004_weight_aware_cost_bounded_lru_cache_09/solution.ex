  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    max_weight = Keyword.fetch!(opts, :max_weight)

    unless is_integer(max_weight) and max_weight > 0 do
      raise ArgumentError, ":max_weight must be a positive integer, got: #{inspect(max_weight)}"
    end

    data_table =
      :ets.new(data_table_name(name), [
        :set,
        :public,
        :named_table,
        read_concurrency: true
      ])

    order_table =
      :ets.new(order_table_name(name), [
        :ordered_set,
        :protected,
        :named_table
      ])

    state = %{
      data_table: data_table,
      order_table: order_table,
      max_weight: max_weight,
      total_weight: 0,
      counter: 0
    }

    {:ok, state}
  end