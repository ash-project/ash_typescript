defmodule AshTypescript.Test.User do
  @moduledoc """
  Test resource representing a user with relationships to todos and settings.
  """
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    primary_read_warning?: false,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "User"
    field_names address_line_1: :address_line1
    argument_names read_with_invalid_arg: [is_active?: :is_active]
  end

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

    attribute :active, :boolean do
      default true
      public? true
    end

    attribute :is_super_admin, :boolean do
      default false
      public? true
    end

    attribute :address_line_1, :string do
      allow_nil? true
      public? true
    end
  end

  relationships do
    has_many :comments, AshTypescript.Test.TodoComment do
      public? true
    end

    has_many :todos, AshTypescript.Test.Todo do
      public? true
    end

    has_many :posts, AshTypescript.Test.Post,
      destination_attribute: :author_id,
      public?: true
  end

  actions do
    defaults [:read]

    read :read_with_invalid_arg do
      argument :is_active?, :boolean
    end

    read :get_by_id do
      get_by :id
    end

    create :create do
      accept [:email, :name, :is_super_admin, :address_line_1]
    end

    update :update do
      accept [:name, :is_super_admin, :address_line_1]
    end

    destroy :destroy do
      accept []
    end
  end

  calculations do
    calculate :self, :struct, AshTypescript.Test.SelfCalculation do
      constraints instance_of: __MODULE__
      public? true

      argument :prefix, :string do
        allow_nil? true
        default nil
      end
    end
  end
end
