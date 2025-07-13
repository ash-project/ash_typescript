defmodule AshTypescript.Test.PostComment do
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets

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