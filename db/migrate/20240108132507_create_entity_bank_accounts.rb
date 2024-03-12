class CreateEntityBankAccounts < ActiveRecord::Migration[7.0]
  def change
    create_table :entity_bank_accounts do |t|
      t.references :bank_accountable, index: true, foraign_key: true, null: false, polymorphic: true
      t.references :bank_account, index: true, foraign_key: true, null: false
      t.timestamps
    end
  end
end
