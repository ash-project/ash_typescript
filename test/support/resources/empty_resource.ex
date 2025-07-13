defmodule AshTypescript.Test.EmptyResource do
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id, public?: false
  end

  actions do
    defaults [:read]
  end
end