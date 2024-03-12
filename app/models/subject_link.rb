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
  belongs_to :depend_subject, class_name: 'Subject', foreign_key: :depend_subject_id

  validates_uniqueness_of :prelate_subject_id, scope: [:depend_subject_id], message: 'la relación ya existe', field_name: false
  validates :prelate_subject_id, presence: true
  validates :depend_subject_id, presence: true

  validates_with NestedDependencyValidator, field_name: false

  scope :in_prelation, -> (aprobadas_ids) {where(prelate_subject_id: aprobadas_ids) }
  scope :not_in_dependency, -> (aprobadas_ids) {where.not(depend_subject_id: aprobadas_ids) }

  def self.subject_tree ids
    auxs = SubjectLink.where(id: ids).joins(:subject).select('subjects.*')
  end

end
