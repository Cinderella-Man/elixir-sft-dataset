  def valid?(secret, code, counter, opts \\ []) do
    look_ahead = Keyword.get(opts, :look_ahead, 0)
    normalized = normalize_code(code)

    Enum.reduce_while(counter..(counter + look_ahead), :error, fn c, _acc ->
      if generate_code(secret, c) == normalized do
        {:halt, {:ok, c + 1}}
      else
        {:cont, :error}
      end
    end)
  end