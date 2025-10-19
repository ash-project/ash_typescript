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

  @doc """
  Gets the TypeScript type to use for untyped maps from application configuration.

  This controls the TypeScript type generated for Ash.Type.Map, Ash.Type.Keyword,
  Ash.Type.Tuple, and unconstrained Ash.Type.Struct types that don't have field
  definitions. The default is `"Record<string, any>"`, but users can configure it
  to use stricter types like `"Record<string, unknown>"` for better type safety.

  ## Configuration

      # Default - allows any value type
      config :ash_typescript, untyped_map_type: "Record<string, any>"

      # Stricter - requires type checking before use
      config :ash_typescript, untyped_map_type: "Record<string, unknown>"

      # Custom - use your own type definition
      config :ash_typescript, untyped_map_type: "MyCustomMapType"

  ## Returns
  A string representing the TypeScript type to use, defaulting to `"Record<string, any>"`.
  """
  def untyped_map_type do
    Application.get_env(:ash_typescript, :untyped_map_type, "Record<string, any>")
  end
end
