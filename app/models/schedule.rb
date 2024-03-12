# == Schema Information
#
# Table name: schedules
#
#  id         :bigint           not null, primary key
#  day        :integer
#  endtime    :time
#  starttime  :time
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  section_id :bigint           not null
#
# Indexes
#
#  index_schedules_on_section_id  (section_id)
#
# Foreign Keys
#
#  fk_rails_...  (section_id => sections.id)
#
class Schedule < ApplicationRecord

  enum day: [:Lunes, :Martes, :Miércoles, :Jueves, :Viernes, :Sábado]  
  belongs_to :section

  validates :day, presence: true
  validates :starttime, presence: true
  validates :endtime, presence: true

  validates_uniqueness_of :section_id, scope: [:day, :starttime], message: 'Ya existe un horario con una hora de enrtada igual para la sección.', field_name: false
  validates_uniqueness_of :section_id, scope: [:day, :endtime], message: 'Ya existe un horario con una hora de salida igual para la sección.', field_name: false

  def short_name
    "#{day[0..1]} #{I18n.l(starttime, format: "%I%P")} #{I18n.l(endtime, format: "a %I%P")}"
    
  end

  def name
    "#{day} #{starttime.strftime("de %I:%M%P") } #{endtime.strftime("a %I:%M%P") }" if (starttime and endtime)
  end

  rails_admin do
    visible false
    show do
      field :name
    end
    edit do
      fields :day, :starttime, :endtime
    end
    export do
      field :name do
        label 'Horario'
      end

    end
  end
end
