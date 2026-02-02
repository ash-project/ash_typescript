# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.InputParsing.InputDataMap do
  @moduledoc """
  NewType for the process_data action's input_data argument.

  Maps is_valid? to isValid to satisfy verifier requirements.
  """
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        item_name: [type: :string, allow_nil?: false],
        is_valid?: [type: :boolean, allow_nil?: true]
      ]
    ]

  # String values are the exact TypeScript names (no additional formatting)
  def typescript_field_names do
    [
      is_valid?: "isValid"
    ]
  end
end
