# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript do
  @moduledoc false

  @doc """
  Gets the type mapping overrides from application configuration.

  This allows users to map Ash types to specific TypeScript types when they can't
  modify the type module itself (e.g., for types from dependencies).

  ## Configuration

      config :ash_typescript,
        type_mapping_overrides: [
          {AshUUID.UUID, "string"},
          {SomeOtherType, "CustomTSType"}
        ]

  ## Returns
  A keyword list of {type_module, typescript_type_string} tuples, or an empty list if not configured.
  """
  def type_mapping_overrides do
    Application.get_env(:ash_typescript, :type_mapping_overrides, [])
  end
end
