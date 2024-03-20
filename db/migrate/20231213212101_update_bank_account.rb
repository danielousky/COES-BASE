class UpdateBankAccount < ActiveRecord::Migration[7.0]
  def change
    remove_column :bank_accounts, :school_id
  end
end
