class School
  # Premio al Mérito Académico: los mejores promedios del año en cada plan de estudio.
  #
  # Criterios de Control de Estudios (Pedro Coronado, FHE, 28-oct-2026), en el orden en que filtran:
  #   1. Primera carrera: la forma de ingreso está marcada así (AdmissionType#first_career).
  #   2. Carga completa: 18 créditos inscritos en cada semestre del año, o 36 si la carrera es anual.
  #      Cuenta lo inscrito y no retirado; las equivalencias no cuentan.
  #   3. Eficiencia 1: ninguna asignatura aplazada ni perdida por inasistencia en la carrera hasta
  #      ese año, y ninguna nota del año sin cargar.
  #   4. Promedio simple del año mayor a 15 (asignaturas numéricas, sin equivalencias).
  #
  # El orden es por promedio simple. Los empates se rompen con el ponderado, que pesa más porque cuenta
  # los créditos, y después con los créditos del año (Daniel, 29-oct-2026).
  #
  # Si en un plan nadie cumple todo, se muestran los CERCANOS que llegaron más lejos: primero quien cumple
  # más criterios, después quien quedó más cerca de la carga y después el mérito. Son solo referencia:
  # sin los criterios cumplidos no se entrega el premio (Pedro, ratificado el 29-oct-2026). Primera
  # carrera no se relaja.
  #
  # Los tres números se cambian por facultad en Configuración General (claves PREMIO_MERITO_*).
  # FHE es la matriz: se prueba aquí y después se copia igual a COES ODON y FAU.
  class PremioMerito
    MINIMOS = {
      creditos_semestre: ['PREMIO_MERITO_CREDITOS_SEMESTRE', 18],
      creditos_anual: ['PREMIO_MERITO_CREDITOS_ANUAL', 36],
      promedio_mayor_a: ['PREMIO_MERITO_PROMEDIO_MAYOR_A', 15]
    }.freeze

    ANIOS_VISIBLES = 8
    CERCANOS = 5
    PERIODOS_REGULARES = %w[01 02].freeze # los intensivos no cuentan
    EN_CURSO_SI_PENDIENTES = 0.1          # fracción de notas sin cargar a partir de la cual el año sigue abierto

    Anio = Struct.new(:numero, :registros, :pendientes) do
      def en_curso?
        pendientes > registros * EN_CURSO_SI_PENDIENTES
      end
    end

    Candidato = Struct.new(:grade_id, :student_id, :study_plan_id, :ci, :nombre, :primera_carrera, :anual,
                           :creditos, :pendientes, :cursadas, :reprobadas, :promedio, :promedio_simple, :puesto,
                           keyword_init: true) do
      def total_de_creditos
        creditos.compact.sum
      end

      # Aprobadas entre cursadas en la carrera hasta el año del premio, como Grade#efficiency.
      def eficiencia
        cursadas.zero? ? 1.0 : (cursadas - reprobadas).fdiv(cursadas)
      end
    end

    # La lista de un plan. falta: nil si son premiados; si no, el criterio que nadie cumplió
    # (:carga_completa, :eficiencia o :promedio) y la lista es la de los más cercanos.
    Grupo = Struct.new(:plan, :estudiantes, :falta) do
      # Plan anual: los créditos van en una sola columna, la del año, y no una por semestre.
      def anual?
        estudiantes.all?(&:anual)
      end
    end

    SIN_PREMIO = {
      carga_completa: 'Nadie de este plan inscribió la carga completa en %<anio>s.',
      eficiencia: 'Nadie de este plan con carga completa llegó a eficiencia 1 en %<anio>s.',
      promedio: 'Nadie de este plan con carga completa y eficiencia 1 pasa del promedio mínimo en %<anio>s.'
    }.freeze

    attr_reader :school, :anios, :anio

    def initialize(school, anio = nil)
      @school = school
      @anios = cargar_anios
      @anio = @anios.find { |a| a.numero == anio.to_i } || @anios.find { |a| !a.en_curso? } || @anios.first
    end

    def minimo(nombre)
      @minimos ||= {}
      @minimos[nombre] ||= begin
        clave, por_defecto = MINIMOS.fetch(nombre)
        valor = GeneralSetup.find_by(clave: clave)&.valor.to_s.strip.tr(',', '.')
        valor.match?(/\A\d+(\.\d+)?\z/) ? valor.to_f : por_defecto
      end
    end

    # [[etiqueta, cuántos quedan], ...]: cada paso aplica un criterio más sobre el anterior.
    def embudo
      @embudo ||= begin
        quedan = candidatos
        [["inscritos en #{anio&.numero}", quedan.size]] +
          criterios.map { |etiqueta, cumple| [etiqueta, (quedan = quedan.select(&cumple)).size] }
      end
    end

    # Con carga completa y sin reprobadas, pero con notas del año sin cargar: aparecen cuando se carguen.
    def esperando_notas
      candidatos.count { |c| c.primera_carrera && carga_completa?(c) && c.reprobadas.zero? && c.pendientes.positive? }
    end

    # Lo que se lee arriba de la lista, en la pantalla y en el Excel.
    def texto_criterios
      "Primera carrera · Carga completa: #{texto_de_carga} · Eficiencia 1 en la carrera hasta #{anio&.numero} · " \
        "Promedio simple del año mayor a #{numero(minimo(:promedio_mayor_a))} · Orden: promedio simple; si " \
        'empatan, ponderado y luego créditos'
    end

    # Los dos semestres del año, con el nombre de sus períodos: 2025-01 y 2025-02.
    def semestres
      PERIODOS_REGULARES.map { |tipo| "#{anio&.numero}-#{tipo}" }
    end

    # Los encabezados de los créditos en la lista de un plan: el año si es anual; si no, sus dos semestres.
    def columnas_de_creditos(grupo)
      grupo.anual? ? ["#{anio.numero} (anual)"] : semestres
    end

    # Las celdas de créditos de un estudiante: [créditos, columnas que ocupa, ¿no llega al mínimo?].
    # Quien cursa por año dentro de un plan semestral ocupa las dos columnas con el total del año.
    def celdas_de_creditos(grupo, candidato)
      if candidato.anual
        total = candidato.total_de_creditos
        corto = total < minimo(:creditos_anual)
        grupo.anual? ? [[total, 1, corto]] : [["#{total} en el año", 2, corto]]
      else
        candidato.creditos.map { |creditos| [creditos, 1, creditos.to_i < minimo(:creditos_semestre)] }
      end
    end

    # La ayuda del encabezado de los créditos, al pasar el ratón.
    def ayuda_de_creditos(grupo)
      carga = if grupo.anual?
                "#{numero(minimo(:creditos_anual))} o más en el año"
              else
                "#{numero(minimo(:creditos_semestre))} o más en cada uno de los dos semestres"
              end
      "Créditos inscritos en #{anio.numero}, sin contar retiros ni equivalencias. Carga completa: #{carga}. " \
        'En rojo, lo que no llega.'
    end

    def aviso_sin_premio(grupo)
      "#{format(SIN_PREMIO.fetch(grupo.falta), anio: anio.numero)} En este plan no hay premio; " \
        "como referencia, los más cercanos (hasta #{CERCANOS})."
    end

    # Un Grupo por plan, ordenados por código.
    def grupos
      @grupos ||= begin
        # Sin créditos en el año no estudió ese año: no entra ni entre los cercanos.
        evaluables = candidatos.select { |c| c.primera_carrera && c.pendientes.zero? && c.total_de_creditos.positive? }
        planes = StudyPlan.where(id: evaluables.map(&:study_plan_id).uniq).index_by(&:id)
        evaluables.group_by(&:study_plan_id)
                  .map { |plan_id, del_plan| grupo_del_plan(planes[plan_id], del_plan) }
                  .sort_by { |grupo| grupo.plan.code.to_s }
      end
    end

    private

    # Solo el régimen que tiene la escuela ese año: ODON es anual, FAU semestral y FHE tiene de los dos.
    def texto_de_carga
      semestral = "#{numero(minimo(:creditos_semestre))} créditos inscritos en cada uno de los dos semestres " \
                  "(#{semestres.join(' y ')})"
      case candidatos.map(&:anual).uniq
      when [true] then "#{numero(minimo(:creditos_anual))} créditos inscritos en el año"
      when [false] then semestral
      else "#{semestral}, o #{numero(minimo(:creditos_anual))} en el año si la carrera es anual"
      end
    end

    # Los que cumplen todo, con medalla. Si nadie, los CERCANOS de la etapa del embudo donde se quedaron todos.
    def grupo_del_plan(plan, del_plan)
      con_carga = del_plan.select { |c| carga_completa?(c) }
      con_eficiencia = con_carga.select { |c| c.reprobadas.zero? }
      premiados = con_eficiencia.select { |c| supera_promedio?(c) }
      return Grupo.new(plan, con_puestos(premiados) { |c| orden_de_merito(c) }, nil) if premiados.any?

      falta, quedan =
        if con_eficiencia.any? then [:promedio, con_eficiencia]
        elsif con_carga.any? then [:eficiencia, con_carga]
        else [:carga_completa, del_plan]
        end
      Grupo.new(plan, con_puestos(quedan) { |c| cercania(c) }.take_while { |c| c.puesto <= CERCANOS }, falta)
    end

    # Primero cuántos criterios cumple, después qué tan cerca quedó de la carga y después el mérito.
    def cercania(candidato)
      cumplidos = [carga_completa?(candidato), candidato.reprobadas.zero?, supera_promedio?(candidato)].count(true)
      [cumplidos, [avance_de_carga(candidato), 1].min.round(2), candidato.eficiencia.round(2), *orden_de_merito(candidato)]
    end

    def supera_promedio?(candidato)
      candidato.promedio_simple.to_f > minimo(:promedio_mayor_a)
    end

    def criterios
      @criterios ||= [
        ['de primera carrera', ->(c) { c.primera_carrera }],
        ['con carga completa', ->(c) { carga_completa?(c) }],
        ['con eficiencia 1', ->(c) { c.reprobadas.zero? && c.pendientes.zero? }],
        ["con promedio simple mayor a #{numero(minimo(:promedio_mayor_a))}", ->(c) { supera_promedio?(c) }]
      ]
    end

    def carga_completa?(candidato)
      avance_de_carga(candidato) >= 1
    end

    # Cuánto llegó al mínimo de créditos (1 = justo el mínimo). En semestral cuenta el semestre más flojo.
    def avance_de_carga(candidato)
      if candidato.anual
        candidato.total_de_creditos.fdiv(minimo(:creditos_anual))
      else
        candidato.creditos.map(&:to_i).min.fdiv(minimo(:creditos_semestre))
      end
    end

    # Simple, luego ponderado, luego créditos; los promedios a dos decimales, como se ven en pantalla.
    def orden_de_merito(candidato)
      [candidato.promedio_simple.to_f.round(2), candidato.promedio.to_f.round(2), candidato.total_de_creditos]
    end

    # De mayor a menor según la clave; los empatados en toda la clave comparten puesto: 1, 1, 3…
    def con_puestos(lista, &clave)
      ordenada = lista.sort_by { |c| clave.call(c).map { |v| -v } + [c.nombre] }
      ordenada.each_with_index do |c, i|
        anterior = ordenada[i - 1] if i.positive?
        c.puesto = anterior && clave.call(anterior) == clave.call(c) ? anterior.puesto : i + 1
      end
    end

    def numero(valor)
      ActiveSupport::NumberHelper.number_to_rounded(valor, precision: 2, strip_insignificant_zeros: true)
    end

    def candidatos
      return [] unless anio

      @candidatos ||= consultar(CANDIDATOS_SQL, escuela: school.id, anio: anio.numero).map do |fila|
        Candidato.new(
          grade_id: fila['grade_id'], student_id: fila['student_id'], study_plan_id: fila['study_plan_id'],
          ci: fila['ci'], nombre: "#{fila['last_name']}, #{fila['first_name']}",
          primera_carrera: ActiveModel::Type::Boolean.new.cast(fila['primera_carrera']),
          anual: ActiveModel::Type::Boolean.new.cast(fila['anual']),
          creditos: [fila['creditos_1'], fila['creditos_2']].map { |cr| cr&.to_i },
          pendientes: fila['pendientes'].to_i, cursadas: fila['cursadas'].to_i, reprobadas: fila['reprobadas'].to_i,
          promedio: fila['promedio']&.to_d, promedio_simple: fila['promedio_simple']&.to_d
        )
      end
    end

    def cargar_anios
      consultar(ANIOS_SQL, escuela: school.id, limite: ANIOS_VISIBLES).map do |fila|
        Anio.new(fila['year'].to_i, fila['registros'].to_i, fila['pendientes'].to_i)
      end
    end

    def consultar(sql, binds)
      binds = binds.merge(
        modalidades: AcademicProcess.modalities.values_at('Semestral', 'Anual'),
        anual: AcademicProcess.modalities['Anual'],
        periodos_regulares: PERIODOS_REGULARES,
        sin_calificar: AcademicRecord.statuses['sin_calificar'],
        retirado: AcademicRecord.statuses['retirado'],
        cursadas: AcademicRecord.statuses.values_at('aprobado', 'aplazado', 'perdida_por_inasistencia'),
        reprobadas: AcademicRecord.statuses.values_at('aplazado', 'perdida_por_inasistencia'),
        numerica: Subject.qualification_types['numerica'],
        equivalencias: Section.modalities.select { |nombre, _| nombre.start_with?('equivalencia') }.values.presence || [-1]
      )
      ActiveRecord::Base.connection.select_all(ActiveRecord::Base.sanitize_sql_array([sql, binds])).to_a
    end

    # Solo los años con registros: hay procesos creados de años que nunca se cargaron en COES.
    ANIOS_SQL = <<~SQL.freeze
      SELECT p.year, COUNT(*) AS registros, COUNT(*) FILTER (WHERE ar.status = :sin_calificar) AS pendientes
      FROM academic_processes ap
      JOIN periods p ON p.id = ap.period_id
      JOIN period_types pt ON pt.id = p.period_type_id
      JOIN enroll_academic_processes eap ON eap.academic_process_id = ap.id
      JOIN academic_records ar ON ar.enroll_academic_process_id = eap.id
      WHERE ap.school_id = :escuela AND ap.modality IN (:modalidades) AND pt.code IN (:periodos_regulares)
      GROUP BY p.year
      ORDER BY p.year DESC
      LIMIT :limite
    SQL

    CANDIDATOS_SQL = <<~SQL.freeze
      WITH ventana AS (
        SELECT ap.id, ap.modality, pt.code AS tipo
        FROM academic_processes ap
        JOIN periods p ON p.id = ap.period_id
        JOIN period_types pt ON pt.id = p.period_type_id
        WHERE ap.school_id = :escuela AND p.year = :anio
          AND ap.modality IN (:modalidades) AND pt.code IN (:periodos_regulares)
      ), registros AS (
        SELECT eap.grade_id, v.modality, v.tipo, ar.status, s.unit_credits AS creditos,
               s.qualification_type, sec.modality AS seccion, q.value AS nota
        FROM ventana v
        JOIN enroll_academic_processes eap ON eap.academic_process_id = v.id
        JOIN academic_records ar ON ar.enroll_academic_process_id = eap.id
        JOIN sections sec ON sec.id = ar.section_id
        JOIN courses c ON c.id = sec.course_id
        JOIN subjects s ON s.id = c.subject_id
        LEFT JOIN LATERAL (
          SELECT value FROM qualifications
          WHERE academic_record_id = ar.id AND definitive
          ORDER BY id DESC LIMIT 1
        ) q ON true
      ), por_periodo AS (
        SELECT grade_id, tipo, bool_or(modality = :anual) AS anual,
               COALESCE(SUM(creditos) FILTER (WHERE status <> :retirado AND seccion NOT IN (:equivalencias)), 0) AS creditos
        FROM registros
        GROUP BY grade_id, tipo
      ), del_anio AS (
        SELECT grade_id,
               COUNT(*) FILTER (WHERE status = :sin_calificar) AS pendientes,
               SUM(creditos * nota) FILTER (WHERE status IN (:cursadas) AND qualification_type = :numerica
                                              AND seccion NOT IN (:equivalencias) AND nota IS NOT NULL)::numeric
                 / NULLIF(SUM(creditos) FILTER (WHERE status IN (:cursadas) AND qualification_type = :numerica
                                                  AND seccion NOT IN (:equivalencias) AND nota IS NOT NULL), 0) AS promedio,
               AVG(nota) FILTER (WHERE status IN (:cursadas) AND qualification_type = :numerica
                                   AND seccion NOT IN (:equivalencias) AND nota IS NOT NULL) AS promedio_simple
        FROM registros
        GROUP BY grade_id
      ), historial AS (
        SELECT eap.grade_id,
               COUNT(*) FILTER (WHERE ar.status IN (:cursadas)) AS cursadas,
               COUNT(*) FILTER (WHERE ar.status IN (:reprobadas)) AS reprobadas
        FROM academic_records ar
        JOIN enroll_academic_processes eap ON eap.id = ar.enroll_academic_process_id
        JOIN academic_processes ap ON ap.id = eap.academic_process_id
        JOIN periods p ON p.id = ap.period_id
        WHERE eap.grade_id IN (SELECT grade_id FROM del_anio) AND p.year <= :anio
        GROUP BY eap.grade_id
      )
      SELECT g.id AS grade_id, g.student_id, g.study_plan_id, u.ci, u.last_name, u.first_name,
             COALESCE(adm.first_career, false) AS primera_carrera,
             bool_or(pp.anual) AS anual,
             MAX(pp.creditos) FILTER (WHERE pp.tipo = '01') AS creditos_1,
             MAX(pp.creditos) FILTER (WHERE pp.tipo = '02') AS creditos_2,
             a.pendientes, a.promedio, a.promedio_simple,
             COALESCE(h.cursadas, 0) AS cursadas, COALESCE(h.reprobadas, 0) AS reprobadas
      FROM del_anio a
      JOIN grades g ON g.id = a.grade_id
      JOIN users u ON u.id = g.student_id
      JOIN por_periodo pp ON pp.grade_id = a.grade_id
      LEFT JOIN admission_types adm ON adm.id = g.admission_type_id
      LEFT JOIN historial h ON h.grade_id = a.grade_id
      GROUP BY g.id, u.id, adm.first_career, a.pendientes, a.promedio, a.promedio_simple, h.cursadas, h.reprobadas
    SQL
  end
end
