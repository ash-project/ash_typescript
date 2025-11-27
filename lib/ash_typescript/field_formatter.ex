# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.FieldFormatter do
  @moduledoc """
  Handles field name formatting for input parameters, output fields, and TypeScript generation.

  Delegates to `AshIntrospection.FieldFormatter` for the core functionality.
  """

  # Delegate all functions to AshIntrospection.FieldFormatter
  defdelegate format_field(field_name, formatter), to: AshIntrospection.FieldFormatter
  defdelegate parse_input_field(field_name, formatter), to: AshIntrospection.FieldFormatter
  defdelegate format_fields(fields, formatter), to: AshIntrospection.FieldFormatter
  defdelegate parse_input_fields(fields, formatter), to: AshIntrospection.FieldFormatter
  defdelegate parse_input_value(value, formatter), to: AshIntrospection.FieldFormatter
end
