  @spec validate(String.t(), map()) :: :ok | {:error, [atom()]}
  def validate(password, %{username: _} = context) do
    cfg = build_config(context)

    violations =
      [
        &check_min_length/2,
        &check_max_length/2,
        &check_uppercase/2,
        &check_lowercase/2,
        &check_digit/2,
        &check_special/2,
        &check_common/2,
        &check_reuse/2,
        &check_username_similarity/2
      ]
      |> Enum.reduce([], fn check, acc ->
        case check.(password, cfg) do
          :ok              -> acc
          {:violation, v}  -> [v | acc]
        end
      end)
      |> Enum.reverse()

    case violations do
      []   -> :ok
      list -> {:error, list}
    end
  end

  def validate(_password, _context) do
    raise ArgumentError, "context map must include the :username key"
  end