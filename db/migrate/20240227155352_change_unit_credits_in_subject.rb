class ChangeUnitCreditsInSubject < ActiveRecord::Migration[7.0]
  def change
    change_column :subjects, :unit_credits, :integer, null: false, default: 5
  end
end
