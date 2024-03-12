# == Schema Information
#
# Table name: payment_reports
#
#  id                        :bigint           not null, primary key
#  amount                    :float
#  payable_type              :string
#  transaction_date          :date
#  transaction_type          :integer
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  origin_bank_id            :bigint           not null
#  payable_id                :bigint
#  receiving_bank_account_id :bigint
#  transaction_id            :string
#
# Indexes
#
#  index_payment_reports_on_origin_bank_id             (origin_bank_id)
#  index_payment_reports_on_payable                    (payable_type,payable_id)
#  index_payment_reports_on_receiving_bank_account_id  (receiving_bank_account_id)
#
# Foreign Keys
#
#  fk_rails_...  (origin_bank_id => banks.id)
#  fk_rails_...  (receiving_bank_account_id => bank_accounts.id) ON DELETE => nullify ON UPDATE => cascade
#
class PaymentReport < ApplicationRecord

  # HISTORY:
  has_paper_trail on: [:create, :destroy, :update]

  before_create :paper_trail_create
  before_destroy :paper_trail_destroy
  before_update :paper_trail_update


  # ASSOCIATIONS:
  belongs_to :origin_bank, class_name: 'Bank', foreign_key: 'origin_bank_id'
  belongs_to :payable, polymorphic: true
  belongs_to :receiving_bank_account, class_name: 'BankAccount'

  has_one_attached :voucher do |attachable|
    attachable.variant :thumb, resize_to_limit: [100,100]
  end

  scope :grades, -> {where(payable_type: 'Grade')}  
  scope :enroll_academic_processes, -> {where(payable_type: 'EnrollAcademicProcess')}  

  # scope :custom_search, -> (keyword) {joins(:user).where("users.ci ILIKE '%#{keyword}%' OR users.first_name ILIKE '%#{keyword}%' OR users.last_name ILIKE '%#{keyword}%' OR users.email ILIKE '%#{keyword}%'") }


  attr_accessor :remove_voucher
  after_save { voucher.purge if remove_voucher.eql? '1' }   

  # VALIDATIONS:
  # validates :payable_id, presence: true
  # validates :payable_type, presence: true
  validates :payable, presence: true
  validates :amount, presence: true
  validates :transaction_id, presence: true
  validates :transaction_type, presence: true
  validates :transaction_date, presence: true
  validates :origin_bank, presence: true
  validates :receiving_bank_account, presence: true
  validates :voucher, presence: true

  enum transaction_type: [:transferencia, :efectivo, :punto_venta]

  def name
    "#{transaction_id} - #{amount_to_bs}"
  end

  def amount_to_bs
    ActionController::Base.helpers.number_to_currency(self.amount, unit: 'Bs.', separator: ",", delimiter: ".")
  end

  rails_admin do
    navigation_label 'Administrativa'
    navigation_icon 'fa-solid fa-cash-register'

    list do
      fields :amount, :transaction_id, :transaction_type, :transaction_date, :origin_bank, :receiving_bank_account

      field :voucher do
        filterable false

        formatted_value do
          if (bindings[:object].voucher&.attached? and bindings[:object].voucher&.representable?)
            bindings[:view].render(partial: "layouts/set_image", locals: {image: bindings[:object].voucher, size: '30x30'})
          else
            false
          end
        end
      end
    end

    show do
      fields :amount, :transaction_id, :transaction_type, :transaction_date, :origin_bank, :receiving_bank_account, :voucher
    end

    edit do
      field :amount
      field :transaction_id do
        html_attributes do
          {:length => 20, :size => 20, :onInput => "$(this).val($(this).val().toUpperCase().replace(/[^0-9]/g,''))"}
        end
      end
      field :payable do
        label 'Entidad a Pagar'
      end
      fields :transaction_type, :transaction_date
      field :origin_bank do
        inline_edit false
        inline_add false
      end
      field :receiving_bank_account do
        inline_edit false
        inline_add false
      end
      field :voucher
    end

    export do
      fields :amount, :transaction_id, :transaction_type, :transaction_date, :origin_bank, :origin_bank
      field :payable_type do
        label 'Tipo'
      end
      field :payable_id do
        label 'Id'
      end

    end
  end  

  private


    def paper_trail_update
      # changed_fields = self.changes.keys - ['created_at', 'updated_at']
      object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
      # self.paper_trail_event = "¡#{object} actualizado en #{changed_fields.to_sentence}"
      self.paper_trail_event = "¡#{object} actualizado!"
    end  

    def paper_trail_create
      object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
      self.paper_trail_event = "¡#{object} registrado!"
    end  

    def paper_trail_destroy
      object = I18n.t("activerecord.models.#{self.model_name.param_key}.one")
      self.paper_trail_event = "¡Reporte de Pago eliminado!"
    end

end
