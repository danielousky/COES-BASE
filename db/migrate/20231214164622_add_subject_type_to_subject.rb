class AddSubjectTypeToSubject < ActiveRecord::Migration[7.0]
  def change
    add_reference :subjects, :subject_type, foreign_key: true, null: false, index: true
  end
end
