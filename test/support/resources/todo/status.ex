defmodule AshTypescript.Test.Todo.Status do
  use Ash.Type.Enum, values: [:pending, :ongoing, :finished, :cancelled]
end
