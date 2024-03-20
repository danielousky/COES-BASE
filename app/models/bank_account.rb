# == Schema Information
#
# Table name: bank_accounts
#
#  id           :bigint           not null, primary key
#  account_type :integer
#  code         :string           not null
#  holder       :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  bank_id      :bigint           not null
#
# Indexes
#
#  index_bank_accounts_on_bank_id  (bank_id)
#
# Foreign Keys
#
#  fk_rails_...  (bank_id => banks.id)
#
class BankAccount < ApplicationRecord

  # ENUMERIZE:
  enum account_type: [:ahorro, :corriente]

  # ASSOCIATIONS:
  belongs_to :bank

  validates :code, presence: true
  validates :holder, presence: true
  validates :account_type, presence: true

  # FUNCTIONS:
  def name
    "#{code} #{holder} - #{account_type} : #{bank&.name}"
  end

  rails_admin do
    # visible false
    navigation_label 'Administrativa'
    navigation_icon 'fa-solid fa-piggy-bank'

    list do
      fields :code, :holder, :bank, :account_type
    end

    edit do
      field :code do
        html_attributes do
          {:length => 20, :size => 20, :onInput => "$(this).val($(this).val().toUpperCase().replace(/[^0-9]/g,''))"}
        end
      end
      field :holder
      field :bank do
        inline_add false
        inline_edit false
      end
      # field :account_type
      field :account_type do
        partial 'bank_accounts/custom_account_type_field'
      end
      # field :short_desc do
      #   help 'A quíen va dirigida la cuenta'
      # end
    end

    export do
      exclude_fields :id, :created_at, :updated_at
    end
  end

end
