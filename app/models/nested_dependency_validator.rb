# Impide prelaciones circulares: que el prerrequisito exija, directa o indirectamente, a la propia materia.
class NestedDependencyValidator < ActiveModel::Validator
  def validate(record)
    return unless record.prelate_subject_id and record.depend_subject_id
    return unless SubjectLink.prerrequisitos_transitivos_ids(record.depend_subject_id, record.id).include?(record.prelate_subject_id)

    materia = record.prelate_subject&.name
    previa = record.depend_subject&.name
    record.errors.add :base, "Prelación circular: #{previa} ya exige, directa o indirectamente, #{materia}"
  end
end
