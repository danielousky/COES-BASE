# == Schema Information
#
# Table name: sections_teachers
#
#  section_id :bigint           not null
#  teacher_id :bigint           not null
#
# Indexes
#
#  index_sections_teachers_on_section_id_and_teacher_id  (section_id,teacher_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (section_id => sections.id)
#  fk_rails_...  (teacher_id => teachers.user_id)
#
class SectionTeacher < ApplicationRecord
  self.table_name = 'sections_teachers'

  belongs_to :section
  belongs_to :teacher#, primary_key: :user_id

  validates_uniqueness_of :teacher_id, scope: [:section_id], message: 'Profesor secundario ya existe para esta sección', field_name: false

  validates :section_id,  presence: true
  validates :teacher_id,  presence: true

end
