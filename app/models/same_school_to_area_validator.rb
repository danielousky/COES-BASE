class SameSchoolToAreaValidator < ActiveModel::Validator
    def validate(record)
        school_ids = record.departaments.map{|dep| dep.school_id}        
        record.errors.add "No es posible registrar una cátedra para más de una", " Escuela" unless school_ids.uniq.count.eql? 1
    end
end
