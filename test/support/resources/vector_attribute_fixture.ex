# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.VectorAttributeFixture do
  @moduledoc """
  Resource with a single Ash.Type.Vector attribute for type alias testing.
  """
  use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :embedding, Ash.Type.Vector, public?: true
  end

  actions do
    defaults [:read, :create]
  end
end
