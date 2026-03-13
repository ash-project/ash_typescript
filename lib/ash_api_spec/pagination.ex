# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshApiSpec.Pagination do
  @moduledoc """
  Represents pagination configuration for a read action.
  """

  @type t :: %__MODULE__{
          offset?: boolean(),
          keyset?: boolean(),
          required?: boolean(),
          countable?: boolean(),
          default_limit: non_neg_integer() | nil,
          max_page_size: non_neg_integer() | nil
        }

  defstruct [
    :offset?,
    :keyset?,
    :required?,
    :countable?,
    :default_limit,
    :max_page_size
  ]
end
