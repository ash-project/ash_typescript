defmodule AshTypescript.Test.MapFieldResource do
  @moduledoc false
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "MapFieldResource"
  end

  attributes do
    uuid_primary_key :id

    attribute :metadata, AshTypescript.Test.CustomMetadata do
      public? true
    end
  end

  actions do
    default_accept :*
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
