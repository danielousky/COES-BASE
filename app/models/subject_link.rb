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

  has_one :school, through: :prelate_subject

  # Convención: prelate_subject es la materia; depend_subject, el prerrequisito que hay que aprobar antes.
  has_paper_trail on: [:create, :destroy, :update]

  validates_uniqueness_of :prelate_subject_id, scope: [:depend_subject_id], message: 'la relación ya existe', field_name: false
  validates :prelate_subject_id, presence: true
  validates :depend_subject_id, presence: true

  validates_with NestedDependencyValidator, field_name: false

  validate :check_prelate_and_depend

  def check_prelate_and_depend
    errors.add(:prelate_subject_id, "asignatura no no puede depender de sí misma") if prelate_subject_id == depend_subject_id
  end


  scope :in_prelation, -> (aprobadas_ids) {where(prelate_subject_id: aprobadas_ids) }
  scope :not_in_dependency, -> (aprobadas_ids) {where.not(depend_subject_id: aprobadas_ids) }

  def self.subject_tree ids
    auxs = SubjectLink.where(id: ids).joins(:subject).select('subjects.*')
  end

  ROMANOS = {'I' => 1, 'II' => 2, 'III' => 3, 'IV' => 4, 'V' => 5, 'VI' => 6, 'VII' => 7, 'VIII' => 8, 'IX' => 9, 'X' => 10}.freeze

  # Ids de todo lo que hay que aprobar, directa o indirectamente, para cursar subject_id.
  # excepto_link_id deja fuera un link (el que se está validando).
  def self.prerrequisitos_transitivos_ids(subject_id, excepto_link_id = nil)
    sql = <<~SQL
      WITH RECURSIVE previas(id) AS (
        SELECT depend_subject_id FROM subject_links WHERE prelate_subject_id = :raiz AND id IS DISTINCT FROM :excepto
        UNION
        SELECT l.depend_subject_id FROM subject_links l JOIN previas p ON l.prelate_subject_id = p.id
        WHERE l.id IS DISTINCT FROM :excepto
      )
      SELECT id FROM previas
    SQL
    connection.select_values(sanitize_sql([sql, raiz: subject_id, excepto: excepto_link_id])).map(&:to_i)
  end

  # Por qué parece estar al revés que `materia` exija `prerrequisito`, o nil si no hay indicio.
  # Las electivas (ordinal 0) no se comparan por semestre.
  def self.advertencia(materia, prerrequisito)
    base_m, num_m = separar_numeral(materia.name)
    base_p, num_p = separar_numeral(prerrequisito.name)
    if num_m and num_p and base_m == base_p and num_p > num_m
      "#{materia.name} exige #{prerrequisito.name}: el número va al revés"
    elsif materia.ordinal.to_i.positive? and prerrequisito.ordinal.to_i > materia.ordinal.to_i
      "#{materia.name} (#{materia.ordinal}.º) exige #{prerrequisito.name}, que es de #{prerrequisito.ordinal}.º"
    end
  end

  def self.separar_numeral(nombre)
    partes = nombre.to_s.strip.upcase.split(/\s+/)
    numero = ROMANOS[partes.last.to_s.delete('()')]
    numero ? [I18n.transliterate(partes[0..-2].join(' ')), numero] : [nil, nil]
  end

  def advertencia
    SubjectLink.advertencia(prelate_subject, depend_subject) if prelate_subject and depend_subject
  end

end
