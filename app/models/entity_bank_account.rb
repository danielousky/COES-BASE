# == Schema Information
#
# Table name: entity_bank_accounts
#
#  id                    :bigint           not null, primary key
#  bank_accountable_type :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  bank_account_id       :bigint           not null
#  bank_accountable_id   :bigint           not null
#
# Indexes
#
#  index_entity_bank_accounts_on_bank_account_id   (bank_account_id)
#  index_entity_bank_accounts_on_bank_accountable  (bank_accountable_type,bank_accountable_id)
#
class EntityBankAccount < ApplicationRecord
    belongs_to :bank_accountable, polymorphic: true
    belongs_to :bank_account

    rails_admin do
        visible false
    end
end
