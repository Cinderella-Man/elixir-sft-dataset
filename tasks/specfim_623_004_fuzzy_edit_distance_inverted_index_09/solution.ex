  @spec do_search(%__MODULE__{}, String.t(), non_neg_integer(), non_neg_integer() | nil) ::
          [%{id: String.t(), score: number()}]