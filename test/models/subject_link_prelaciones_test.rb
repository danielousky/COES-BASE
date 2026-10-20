require "test_helper"

# Candado de prelaciones (Fase 1).
#
# Convención: SubjectLink.prelate_subject es la materia; depend_subject, el prerrequisito.
#
# Cubre:
#   - una prelación ya guardada sigue siendo válida (antes NestedDependencyValidator daba "anidada")
#   - las prelaciones circulares se bloquean, directas e indirectas
#   - el formulario de la materia (depend_subject_ids=) advierte si el prerrequisito parece al revés
#     y sólo guarda si se confirma; las electivas no se comparan por semestre
#   - PaperTrail registra altas y bajas de prelaciones
class SubjectLinkPrelacionesTest < ActiveSupport::TestCase
  def setup
    @uid = SecureRandom.hex(4)
    faculty = Faculty.create!(name: "Fac Prel #{@uid}", code: "FP#{@uid}",
                              contact_email: "fp#{@uid}@test.com", coes_boss_name: "Jefe #{@uid}")
    @school = School.create!(name: "Esc Prel #{@uid}", code: "EP#{@uid}", faculty: faculty)
    @area = Area.create!(name: "Area #{@uid}", school: @school)
    @departament = Departament.create!(name: "Dpto #{@uid}", school: @school)
    @departament.areas << @area
    @tipo = SubjectType.find_or_create_by!(code: "PRL#{("a".."z").to_a.sample(8).join}") { |st| st.name = "OBLIGATORIA #{@uid}" }
  end

  def materia(nombre, ordinal)
    Subject.create!(code: "P#{@uid}#{rand(10**6)}", name: "#{nombre} #{@uid}",
                    ordinal: ordinal, subject_type: @tipo, qualification_type: :numerica, unit_credits: 3,
                    area: @area, departament: @departament, school: @school)
  end

  def exigir(materia, previa)
    SubjectLink.create!(prelate_subject: materia, depend_subject: previa)
  end

  test "una prelación ya guardada sigue siendo válida" do
    a = materia('Curso A', 1)
    b = materia('Curso B', 2)
    link = exigir(b, a)

    assert link.reload.valid?, link.errors.full_messages.to_sentence
  end

  test "bloquea una prelación circular indirecta" do
    a = materia('Curso A', 1)
    b = materia('Curso B', 2)
    c = materia('Curso C', 3)
    exigir(b, a)
    exigir(c, b)

    link = SubjectLink.new(prelate_subject: a, depend_subject: c)
    assert_not link.valid?
    assert_match(/circular/, link.errors.full_messages.to_sentence)
  end

  test "el formulario guarda un prerrequisito de un semestre anterior sin pedir confirmación" do
    a = materia('Curso A', 1)
    b = materia('Curso B', 2)

    b.depend_subject_ids = ['', a.id.to_s]
    assert b.save, b.errors.full_messages.to_sentence
    assert_equal [a.id], b.reload.depend_subject_ids
  end

  test "el formulario advierte un prerrequisito de un semestre posterior y lo guarda sólo si se confirma" do
    primero = materia('Curso Uno', 1)
    quinto = materia('Curso Cinco', 5)

    primero.depend_subject_ids = [quinto.id]
    assert_not primero.save
    assert_match(/al revés/, primero.errors[:depend_subjects].to_sentence)
    assert_equal [quinto.id], primero.depend_subject_ids, 'conserva la selección para volver a mostrarla'
    assert_equal [quinto.id], primero.depend_subjects.map(&:id), 'el formulario la vuelve a dibujar con lo elegido'
    assert_empty SubjectLink.where(prelate_subject_id: primero.id)

    primero.confirmar_prelaciones = true
    assert primero.save, primero.errors.full_messages.to_sentence
    assert_equal [quinto.id], primero.reload.depend_subject_ids
  end

  test "advierte el par I y II invertido aunque sean del mismo semestre" do
    uno = Subject.create!(code: "P#{@uid}1", name: "TALLER DE CINE #{@uid} I", ordinal: 3, subject_type: @tipo,
                          qualification_type: :numerica, unit_credits: 3, area: @area, departament: @departament, school: @school)
    dos = Subject.create!(code: "P#{@uid}2", name: "TALLER DE CINE #{@uid} II", ordinal: 3, subject_type: @tipo,
                          qualification_type: :numerica, unit_credits: 3, area: @area, departament: @departament, school: @school)

    assert_match(/número va al revés/, SubjectLink.advertencia(uno, dos).to_s)
    assert_nil SubjectLink.advertencia(dos, uno)

    tv_uno = Subject.create!(code: "P#{@uid}3", name: "LENGUAJE DE LA TV #{@uid} (I)", ordinal: 0, subject_type: @tipo,
                             qualification_type: :numerica, unit_credits: 3, area: @area, departament: @departament, school: @school)
    tv_dos = Subject.create!(code: "P#{@uid}4", name: "LENGUAJE DE LA TV #{@uid} (II)", ordinal: 0, subject_type: @tipo,
                             qualification_type: :numerica, unit_credits: 3, area: @area, departament: @departament, school: @school)
    assert_match(/número va al revés/, SubjectLink.advertencia(tv_uno, tv_dos).to_s, 'reconoce el numeral entre paréntesis')
  end

  test "una electiva (ordinal 0) puede exigir una materia de cualquier semestre" do
    electiva = materia('Electiva', 0)
    sexto = materia('Curso Seis', 6)

    electiva.depend_subject_ids = [sexto.id]
    assert electiva.save, electiva.errors.full_messages.to_sentence
  end

  test "el formulario bloquea la prelación circular" do
    a = materia('Curso A', 1)
    b = materia('Curso B', 2)
    exigir(b, a)

    a.depend_subject_ids = [b.id]
    a.confirmar_prelaciones = true
    assert_not a.save
    assert_match(/circular/, a.errors[:depend_subjects].to_sentence)
  end

  test "queda historial al agregar y al quitar una prelación" do
    a = materia('Curso A', 1)
    b = materia('Curso B', 2)

    b.depend_subject_ids = [a.id]
    b.save!
    link_id = b.depend_links.first.id
    b.depend_subject_ids = []
    b.save!

    eventos = PaperTrail::Version.where(item_type: 'SubjectLink', item_id: link_id).order(:id).pluck(:event)
    assert_equal %w[create destroy], eventos
    assert_empty b.reload.depend_links
  end
end
