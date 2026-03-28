# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Suggestion do
  @moduledoc """
  NewType wrapping :map with field constraints for testing codegen field selection.

  This type has no typescript_field_names/0 callback — fields are already TS-safe.
  Used to verify that codegen correctly unwraps NewTypes before classifying return types.
  """
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        name: [type: :string, allow_nil?: false],
        category: [type: :string, allow_nil?: true],
        score: [type: :integer, allow_nil?: false]
      ]
    ]
end
