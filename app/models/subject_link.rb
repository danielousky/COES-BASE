# == Schema Information
#
# Table name: subject_links
#
#  id                 :bigint           not null, primary key
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  depend_subject_id  :bigint           not null
#  prelate_subject_id :bigint           not null
#
# Indexes
#
#  index_subject_links_on_depend_subject_id   (depend_subject_id)
#  index_subject_links_on_prelate_subject_id  (prelate_subject_id)
#  link_parent_depend                         (prelate_subject_id,depend_subject_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (depend_subject_id => subjects.id)
#  fk_rails_...  (prelate_subject_id => subjects.id)
#
class SubjectLink < ApplicationRecord

  belongs_to :prelate_subject, class_name: 'Subject', foreign_key: :prelate_subject_id
  belongs_to :subject

  has_one :school, through: :subject
  validates_uniqueness_of :prelate_subject_id, scope: [:subject_id], message: 'la relación ya existe', field_name: false
  validates :prelate_subject_id, presence: true
  validates :subject_id, presence: true

  validates_with NestedDependencyValidator, field_name: false

  validate :check_prelate_and_depend

  def check_prelate_and_depend
    errors.add(:prelate_subject_id, "asignatura no no puede depender de sí misma") if prelate_subject_id == subject_id
  end


  scope :in_prelation, -> (ids) {where(prelate_subject_id: ids) }
  scope :not_in_dependency, -> (ids) {where.not(subject_id: ids) }

  def self.subject_tree ids
    auxs = SubjectLink.where(id: ids).joins(:subject).select('subjects.*')
  end

end
