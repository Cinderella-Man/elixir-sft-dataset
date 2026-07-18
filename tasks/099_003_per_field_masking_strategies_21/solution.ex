  @doc """
  Scrubs credit-card numbers, e-mail addresses, and SSN patterns from `string`.

  ## Examples

      iex> masker = FieldMasker.new(%{})
      iex> FieldMasker.mask_string(masker, "call 4111-1111-1111-1234")
      "call ****-****-****-1234"

  """
  @spec mask_string(t(), String.t()) :: String.t()
  def mask_string(%__MODULE__{}, string) when is_binary(string) do
    string
    |> mask_emails()
    |> mask_credit_cards()
    |> mask_ssns()
  end