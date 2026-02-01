# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Todo.Status do
  @moduledoc """
  Todo status enumeration.
  """
  use Ash.Type.Enum, values: [:pending, :ongoing, :finished, :cancelled]
end
