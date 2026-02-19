# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Todo.Percentage do
  @moduledoc """
  A NewType wrapping :float with a custom typescript_type_name.
  Demonstrates that NewTypes with typescript_type_name are respected.
  """
  use Ash.Type.NewType, subtype_of: :float

  def typescript_type_name, do: "CustomTypes.Percentage"
end
