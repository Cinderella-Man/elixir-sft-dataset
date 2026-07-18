  @doc """
  Scrubs the three sensitive patterns (credit cards, emails, SSNs) from a raw
  string and returns `{scrubbed_string, report}`.

  `:keys_masked` is always `0` for this function; the other three counters
  report how many matches of each pattern were masked.
  """
  @spec redact_string(t(), String.t()) :: {String.t(), report()}
  def redact_string(%__MODULE__{} = _redactor, string) when is_binary(string) do
    scrub_string(string)
  end