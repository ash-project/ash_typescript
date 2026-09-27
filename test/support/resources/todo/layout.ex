# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Todo.Layout do
  @moduledoc """
  A NewType wrapping an unconstrained :map with a custom typescript_type_name.
  Demonstrates that map NewTypes with typescript_type_name are respected.
  """
  use Ash.Type.NewType, subtype_of: :map

  def typescript_type_name, do: "CustomTypes.Layout"
end
