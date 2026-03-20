class AddIndexToVersionsWhodunnit < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :versions, [:whodunnit, :created_at], algorithm: :concurrently,
              name: 'index_versions_on_whodunnit_and_created_at'
  end
end
