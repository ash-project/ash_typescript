# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TypedChannel.Info do
  @moduledoc """
  Provides introspection functions for AshTypescript.TypedChannel configuration.
  """

  use Spark.InfoGenerator,
    extension: AshTypescript.TypedChannel.Dsl,
    sections: [:typed_channel]

  @doc "Whether or not a given module uses the AshTypescript.TypedChannel DSL."
  @spec typed_channel?(module()) :: boolean()
  def typed_channel?(module) when is_atom(module) do
    Spark.Dsl.is?(module, AshTypescript.TypedChannel)
  rescue
    _ -> false
  end
end
