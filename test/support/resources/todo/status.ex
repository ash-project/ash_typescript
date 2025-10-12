# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Todo.Status do
  @moduledoc """
  Todo status enumeration.
  """
  use Ash.Type.Enum, values: [:pending, :ongoing, :finished, :cancelled]
end
