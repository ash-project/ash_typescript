defmodule AshTypescript.Test.TodoStatus do
  use Ash.Type.Enum, values: [:pending, :ongoing, :finished, :cancelled]
end