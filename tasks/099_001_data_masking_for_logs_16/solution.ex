  @doc """
  Masks credit card numbers, email addresses, and SSN patterns inside a raw string.

  * SSNs (`\\d{3}-\\d{2}-\\d{4}`): replaced with `***-**-****`. SSNs are masked
    first so that adjacent SSNs are never swallowed by the broader credit card
    pattern (which would otherwise leave a trailing four digits visible).
  * Credit cards (13–19 digits, optionally separated by spaces or hyphens):
    all digits except the final four are replaced with `*`, separators kept.
  * Emails: the local part keeps only its first character; the rest becomes `***`.
  """
  @spec mask_string(t(), String.t()) :: String.t()
  def mask_string(%__MODULE__{}, string) when is_binary(string) do
    string
    |> mask_ssns()
    |> mask_credit_cards()
    |> mask_emails()
  end