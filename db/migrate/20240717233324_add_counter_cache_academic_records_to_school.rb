class AddCounterCacheAcademicRecordsToSchool < ActiveRecord::Migration[7.0]
  def change
    add_column :schools, :academic_records_count, :integer, default: 0 
    up_only do
      School.all.each.map{|es| es.update(academic_records_count: es.academic_records.count)}
    end
  end
end
