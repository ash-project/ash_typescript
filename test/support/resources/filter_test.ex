defmodule AshTypescript.FilterTest.TestPost do
  use Ash.Resource,
    domain: AshTypescript.FilterTest.TestDomain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :content, :string, public?: true
    attribute :published, :boolean, default: false, public?: true
    attribute :view_count, :integer, default: 0, public?: true
    attribute :rating, :decimal, public?: true
    attribute :published_at, :utc_datetime, public?: true
    attribute :tags, {:array, :string}, public?: true

    attribute :status, :atom do
      constraints one_of: [:draft, :published, :archived]
      public? true
    end

    attribute :metadata, :map, public?: true
  end

  relationships do
    belongs_to :author, AshTypescript.FilterTest.TestUser, public?: true

    has_many :comments, AshTypescript.FilterTest.TestComment,
      destination_attribute: :post_id,
      public?: true
  end

  actions do
    defaults [:create, :read, :update, :destroy]
  end
end

defmodule AshTypescript.FilterTest.TestUser do
  use Ash.Resource,
    domain: AshTypescript.FilterTest.TestDomain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :email, :string, allow_nil?: false, public?: true
    attribute :active, :boolean, default: true, public?: true
  end

  relationships do
    has_many :posts, AshTypescript.FilterTest.TestPost,
      destination_attribute: :author_id,
      public?: true
  end

  actions do
    defaults [:create, :read, :update, :destroy]
  end
end

defmodule AshTypescript.FilterTest.TestComment do
  use Ash.Resource,
    domain: AshTypescript.FilterTest.TestDomain,
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
    belongs_to :post, AshTypescript.FilterTest.TestPost, public?: true
    belongs_to :author, AshTypescript.FilterTest.TestUser, public?: true
  end

  actions do
    defaults [:create, :read, :update, :destroy]
  end
end

defmodule AshTypescript.FilterTest.NoRelationshipsResource do
  use Ash.Resource,
    domain: AshTypescript.FilterTest.TestDomain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTypescript.FilterTest.EmptyResource do
  use Ash.Resource,
    domain: AshTypescript.FilterTest.TestDomain,
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

defmodule AshTypescript.FilterTest.TestDomain do
  use Ash.Domain

  resources do
    resource AshTypescript.FilterTest.TestPost
    resource AshTypescript.FilterTest.TestUser
    resource AshTypescript.FilterTest.TestComment
    resource AshTypescript.FilterTest.NoRelationshipsResource
    resource AshTypescript.FilterTest.EmptyResource
  end
end