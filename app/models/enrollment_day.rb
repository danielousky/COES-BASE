# == Schema Information
#
# Table name: enrollment_days
#
#  id                    :bigint           not null, primary key
#  by_before_process     :boolean          default(TRUE), not null
#  max_grades            :integer
#  slot_duration_minutes :integer
#  start                 :datetime
#  total_duration_hours  :integer
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  academic_process_id   :bigint           not null
#
# Indexes
#
#  index_enrollment_days_on_academic_process_id  (academic_process_id)
#
# Foreign Keys
#
#  fk_rails_...  (academic_process_id => academic_processes.id)
#
class EnrollmentDay < ApplicationRecord

  #RELATIONSHIPS:
  belongs_to :academic_process
  has_one :school, through: :academic_process 
  has_one :period, through: :academic_process 
  
  # VALIDACIONES
  validates :academic_process_id, presence: true
  validates :start, presence: true
  validates :total_duration_hours, presence: true
  validates :max_grades, presence: true
  validates :slot_duration_minutes, presence: true

  validates_with UniqEnrollmentDayValidator, field_name: false, if: :new_record?

  #CALLBACK
  after_destroy :clean_grades_with_appointment_time

  #SCOPE
  scope :current_process, -> (academic_process_id) { of_today.where(academic_process_id: academic_process_id)}
  scope :of_today, -> {where(start: Time.zone.now.all_day)}
  scope :expired, -> { where('start < ?', Time.current.beginning_of_day) }
  
  def active_now?
    Time.zone.now > self.start and Time.zone.now < self.start+total_duration_hours.hours
  end

  #MÉTODOS

  #CSV:
  def name_to_file
    "#{academic_process.school.code}_#{academic_process.process_name}_#{start.strftime('%Y%m%d')}_#{self.id}"
  end

  def own_grades_to_csv
    grades = own_grades_sort_by_appointment
    ap_id = academic_process.id

    if by_before_process && academic_process.process_before
      eap_data = EnrollAcademicProcess.where(academic_process_id: academic_process.process_before_id, grade_id: grades.map(&:id)).index_by(&:grade_id)
    end

    eap_statuses = EnrollAcademicProcess.where(academic_process_id: ap_id, grade_id: grades.map(&:id)).index_by(&:grade_id)

    CSV.generate do |csv|
      csv << ['Estado Insc', 'Sede', 'Cédula', 'Apellidos y Nombres', 'Correo', 'Est. Permanencia', 'Desde', 'Hasta', 'Eficiencia', 'Promedio', 'Ponderado']

      slot_number = 0
      grades.group_by(&:appointment_time).each do |appointment_time, slot_grades|
        slot_number += 1
        csv << ["Franja #{slot_number}: #{slot_grades.first.appointment_from} - #{slot_grades.first.appointment_to} (#{slot_grades.size} estudiantes)"]

        slot_grades.each do |grade|
          user = grade.user
          obj = (by_before_process && eap_data) ? (eap_data[grade.id] || grade) : grade
          estado = eap_statuses[grade.id]&.enroll_status&.titleize || 'Sin Inscripción'

          csv << [estado, grade.student.sede, user.ci, user.reverse_name, user.email, grade.current_permanence_status&.titleize, grade.appointment_from, grade.appointment_to, obj.efficiency, obj.simple_average, obj.weighted_average]
        end
      end
    end
  end

  def total_timeslots #total_franjas
    (slot_duration_minutes.eql? 0) ? 0 : (self.total_duration_hours/self.slot_duration_minutes.to_f*60).to_i
  end

  def grades_by_timeslot #grado_x_franja 
    if self.total_timeslots > max_grades 
      return max_grades 
    else
      (self.total_timeslots > 0) ? (max_grades/total_timeslots) : 0
    end
  end

  def mod_to_grades
    (total_timeslots.eql? 0) ? 0 : max_grades%total_timeslots
  end


  def own_grades
    end_time = self.start + total_duration_hours.hours + slot_duration_minutes.minutes
    self.school.grades.where(appointment_time: self.start..end_time)
  end

  def own_grades_count
    self.own_grades.count
  end

  def own_grades_sort_by_appointment
    grades = own_grades.to_a

    if by_before_process && academic_process.process_before
      eap_numbers = EnrollAcademicProcess
        .where(academic_process_id: academic_process.process_before_id)
        .pluck(:grade_id, :efficiency, :simple_average, :weighted_average)
        .each_with_object({}) { |(gid, eff, sa, wa), h| h[gid] = [eff || 0, sa || 0, wa || 0] }

      grades.sort_by { |g| [g.appointment_time, g.duration_slot_time] + eap_numbers.fetch(g.id, [0, 0, 0]).map(&:-@) }
    else
      grades.sort_by { |g| [g.appointment_time, g.duration_slot_time, -(g.efficiency || 0), -(g.simple_average || 0), -(g.weighted_average || 0)] }
    end
  end

  def own_grades_sort_by_numbers
    self.own_grades.order([efficiency: :desc, simple_average: :desc, weighted_average: :desc])
  end

  def clean_grades_with_appointment_time
    self.own_grades.update_all(appointment_time: nil, duration_slot_time: nil)
  end

end
