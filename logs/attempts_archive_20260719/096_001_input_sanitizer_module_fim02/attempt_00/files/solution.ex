  @spec filename(String.t()) :: {:ok, String.t()} | {:error, :empty}
  def filename(input) when is_binary(input) do
    sanitized =
      input
      # 1. Strip null bytes.
      |> String.replace("\0", "")
      # 2. Strip path separators (both flavours).  "../../etc/passwd" becomes
      #    "....etcpasswd" — the dot runs are neutralised in steps 4–5.
      |> String.replace("/", "")
      |> String.replace("\\", "")
      # 3. Keep only the safe character set.
      |> String.replace(~r/[^a-zA-Z0-9_\-.]/, "")
      # 4. Collapse runs of two or more consecutive dots to a single dot.
      #    Handles both traversal remnants ("....etcpasswd" → ".etcpasswd")
      #    and double-dot typos ("hello..world" → "hello.world").
      |> String.replace(~r/\.{2,}/, ".")
      # 5. Strip leading/trailing dots left over after collapsing
      #    (e.g. ".etcpasswd" → "etcpasswd").
      |> String.trim(".")

    if sanitized == "" do
      {:error, :empty}
    else
      {:ok, sanitized}
    end
  end