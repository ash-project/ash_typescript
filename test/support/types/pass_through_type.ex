# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.PassThroughType do
  @moduledoc """
  A minimal custom type for test-local type modules: `use Ash.Type` with
  values passed through unchanged. Options: `storage:` (the `storage_type/1`,
  default `:map`) and `constraints:` (the `constraints/0`, default none).

      defmodule Coordinates do
        use AshTypescript.Test.PassThroughType
      end

      defmodule Code do
        use AshTypescript.Test.PassThroughType, storage: :string
      end
  """

  defmacro __using__(opts) do
    storage = Keyword.get(opts, :storage, :map)
    constraints = Keyword.get(opts, :constraints, [])

    quote do
      use Ash.Type

      @impl true
      def constraints, do: unquote(constraints)
      @impl true
      def storage_type(_), do: unquote(storage)
      @impl true
      def cast_input(value, _), do: {:ok, value}
      @impl true
      def cast_stored(value, _), do: {:ok, value}
      @impl true
      def dump_to_native(value, _), do: {:ok, value}
    end
  end
end
