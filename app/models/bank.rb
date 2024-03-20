# == Schema Information
#
# Table name: banks
#
#  id         :bigint           not null, primary key
#  code       :string
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Bank < ApplicationRecord

  # HISTORY:
  has_paper_trail on: [:create, :destroy, :update]

  before_create :paper_trail_create
  before_destroy :paper_trail_destroy
  before_update :paper_trail_update

  # ASSOCIATION:
  has_many :payment_reports, foreign_key: :origin_bank_id

  # VALIDATIONS:
  validates :code, presence: true 
  validates :name, presence: true 


  # FUNCTIONS:
  def total_payment_reports
    payment_reports.count
  end

  # RAILS_ADMIN:
  rails_admin do
    navigation_label 'Administrativa'
    navigation_icon 'fa-solid fa-bank'

    list do
      fields :code, :name
      field :total_payment_reports do
        label 'Total Reporte Pagos'
      end
    end

    show do
      fields :code, :name
    end

    edit do
      fields :code, :name
    end

    export do
      fields :code, :name
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
      self.paper_trail_event = "¡Banco eliminado!"
    end



end
