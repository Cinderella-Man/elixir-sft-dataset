  @doc """
  Masks sensitive data in a map, keyword list, or string.

  * Maps and keyword lists are walked recursively. Values under sensitive keys
    are replaced with `"[MASKED]"` regardless of the original value. Non-sensitive
    keys are preserved, and their values continue to be scrubbed.
  * Plain lists (and lists of maps / keyword lists) are walked element-by-element.
  * String values are always passed through `mask_string/2`, so embedded PII
    (credit cards, emails, SSNs) is scrubbed everywhere — even under keys
    that were not marked sensitive.
  * Structs and other terms are returned unchanged.
  """
  @spec mask(t(), term()) :: term()
  def mask(%__MODULE__{} = masker, data), do: do_mask(masker, data)