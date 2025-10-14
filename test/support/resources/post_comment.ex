# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.PostComment do
  @moduledoc """
  Test resource for post comments.
  """
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "PostComment"
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :content, :string, allow_nil?: false, public?: true
    attribute :approved, :boolean, default: false, public?: true
  end

  relationships do
    belongs_to :post, AshTypescript.Test.Post, public?: true
    belongs_to :author, AshTypescript.Test.User, public?: true
  end

  actions do
    defaults [:create, :read, :update, :destroy]
  end
end
