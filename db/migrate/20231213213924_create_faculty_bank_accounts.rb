class CreateFacultyBankAccounts < ActiveRecord::Migration[7.0]
  def change
    create_table :faculty_bank_accounts do |t|
      t.references :faculty, index: true, foraign_key: true, null: false
      t.references :bank_account, index: true, foraign_key: true, null: false
      t.timestamps
    end
  end
end
