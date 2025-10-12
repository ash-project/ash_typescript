# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.NotExposed do
  @moduledoc """
  Test resource not exposed to TypeScript generation.
  """
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    primary_read_warning?: false

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :email, :string do
      allow_nil? false
      public? true
    end
  end

  relationships do
    belongs_to :todo, AshTypescript.Test.Todo do
      public? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:email, :name]
    end

    update :update do
      accept [:name]
    end

    destroy :destroy do
      accept []
    end
  end
end
