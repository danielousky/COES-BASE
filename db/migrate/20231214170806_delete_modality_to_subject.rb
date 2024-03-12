class DeleteModalityToSubject < ActiveRecord::Migration[7.0]
  def change
    remove_column :subjects, :modality
  end
end
