  def apply_codes(codes, order_total, opts \\ [])
      when is_list(codes) and is_integer(order_total) and order_total >= 0 do
    GenServer.call(__MODULE__, {:apply, codes, order_total, opts})
  end