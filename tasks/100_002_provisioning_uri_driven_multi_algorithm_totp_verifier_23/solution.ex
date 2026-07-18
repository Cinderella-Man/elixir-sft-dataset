  @doc """
  Returns `true` when `code` matches the code for the exact step containing `unix_time`.

  There is no drift window: codes from the previous or next step are rejected. `code` may
  be a string or an integer; it is zero-padded on the left to `config.digits` characters
  before being compared in constant time.
  """
  @spec verify(t(), String.t() | integer(), integer()) :: boolean()
  def verify(config, code, unix_time) when is_integer(unix_time) do
    candidate =
      code
      |> to_string()
      |> String.pad_leading(config.digits, "0")

    constant_time_equal?(candidate, code_at(config, unix_time))
  end