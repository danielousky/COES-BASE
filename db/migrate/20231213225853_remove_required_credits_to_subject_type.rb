class RemoveRequiredCreditsToSubjectType < ActiveRecord::Migration[7.0]
  def change
    remove_column :subject_types, :required_credits
  end
end
