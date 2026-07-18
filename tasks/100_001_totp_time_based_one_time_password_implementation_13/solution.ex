  @doc """
  Validates `code` against `secret`, tolerating clock drift.

  ## Options

    * `:time`   — UNIX seconds to validate against (default: current time)
    * `:window` — number of 30-second steps accepted in each direction (default: 1)
  """
  @spec valid?(String.t(), String.t() | integer(), keyword()) :: boolean()
  def valid?(secret, code, opts \\ []) do
    time = Keyword.get(opts, :time, :os.system_time(:second))
    window = Keyword.get(opts, :window, 1)
    expected = normalize_code(code)

    Enum.any?(-window..window, fn offset ->
      t = time + offset * @period
      secure_equal?(generate_code(secret, t), expected)
    end)
  end