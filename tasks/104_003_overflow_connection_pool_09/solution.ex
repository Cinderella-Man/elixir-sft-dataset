  @impl true
  def init(opts) do
    size = Keyword.get(opts, :size, 5)
    max_overflow = Keyword.get(opts, :max_overflow, 0)
    create = Keyword.get(opts, :create, fn -> make_ref() end)
    destroy = Keyword.get(opts, :destroy, fn _ -> :ok end)

    cond do
      not (is_integer(size) and size >= 0) ->
        {:stop, {:invalid_option, :size}}

      not (is_integer(max_overflow) and max_overflow >= 0) ->
        {:stop, {:invalid_option, :max_overflow}}

      not is_function(create, 0) ->
        {:stop, {:invalid_option, :create}}

      not is_function(destroy, 1) ->
        {:stop, {:invalid_option, :destroy}}

      true ->
        available = for _ <- 1..size//1, do: create.()

        {:ok,
         %__MODULE__{
           available: available,
           total: size,
           size: size,
           max_overflow: max_overflow,
           create: create,
           destroy: destroy
         }}
    end
  end