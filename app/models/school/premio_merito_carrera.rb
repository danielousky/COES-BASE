class School
  # Premio al Mérito por la CARRERA, para la escuela que tenga PREMIO_MERITO_POR_CARRERA en SI en Configuración
  # General (ODON; Daniel con la Dra. Sandra, jefa de CE de Odontología, 9-nov-2026). Con NO, el premio es por el
  # año (PremioMerito), como en FHE y FAU.
  #
  # En ODON se cursa el año completo o se retira entero, y cada año tiene otra carga (48, 46, 54, 53 y 14 créditos):
  # los créditos no dicen nada del mérito, y el promedio de un solo año favorece a 5º, que son tres notas. Por eso
  # cuenta toda la carrera hasta el período:
  #   entran   primera carrera, sin equivalencias (no se sabe cómo le fue en el otro lugar), sin retiros,
  #            eficiencia 1 y sin notas del período por cargar;
  #   orden    promedio simple de la carrera; si empatan, el ponderado.
  # Una lista General y una por año de la carrera, con los 10 primeros de cada una. Si empatan en el 10º, entran
  # todos (Daniel: es para limpiar la vista, no tan estricto).
  # FHE es la matriz: se prueba aquí y después se copia igual a COES ODON y FAU.
  class PremioMeritoCarrera
    CLAVE = 'PREMIO_MERITO_POR_CARRERA'.freeze
    TOP = 10

    Candidato = Struct.new(:grade_id, :student_id, :ci, :nombre, :anio_de_carrera, :anual, :primera_carrera,
                           :pendientes, :cursadas, :reprobadas, :retiros, :equivalencias, :promedio_simple,
                           :promedio, :puesto, keyword_init: true) do
      def eficiencia
        cursadas.zero? ? 1.0 : (cursadas - reprobadas).fdiv(cursadas)
      end

      def elegible?
        primera_carrera && equivalencias.zero? && retiros.zero? && reprobadas.zero?
      end

      def cumple?
        elegible? && pendientes.zero? && !promedio_simple.nil?
      end

      # Cumpliría, pero tiene notas del período sin cargar: aparece cuando se carguen.
      def esperando_notas?
        elegible? && pendientes.positive?
      end
    end

    # La General o la de un año de la carrera. estudiantes: los primeros, cada uno con su puesto en esta lista.
    Lista = Struct.new(:clave, :titulo, :estudiantes, :cumplen, :inscritos, :esperando) do
      def general?
        clave == 'general'
      end
    end

    def self.activo?
      GeneralSetup.find_by(clave: CLAVE)&.valor.to_s.strip.upcase.in?(%w[SI SÍ])
    end

    attr_reader :school

    # Los años que se pueden ver y cuál se abre son los mismos del premio por año.
    delegate :anios, :anio, to: :@por_anio

    def initialize(school, anio = nil)
      @school = school
      @por_anio = PremioMerito.new(school, anio)
    end

    def por_carrera?
      true
    end

    def excel
      PremioMeritoCarreraExcel.new(self)
    end

    def listas
      @listas ||= [lista('general', 'General', candidatos)] +
                  candidatos.map(&:anio_de_carrera).uniq.sort.map do |numero|
                    lista(numero.to_s, "#{numero}º #{unidad}", candidatos.select { |c| c.anio_de_carrera == numero })
                  end
    end

    # ODON es anual; en un plan semestral el ordinal de la asignatura es el semestre.
    def unidad
      candidatos.all?(&:anual) ? 'año' : 'semestre'
    end

    def texto_criterios
      hasta = "hasta #{anio&.numero}"
      "Primera carrera, sin equivalencias ni retiros · Eficiencia 1 en la carrera #{hasta} · Orden: promedio " \
        "simple de la carrera #{hasta}; si empatan, el ponderado · Los #{TOP} primeros de cada lista; si empatan " \
        "en el #{TOP}º puesto, entran todos"
    end

    # La línea sobre cada lista, en la pantalla y en el Excel.
    def resumen(lista)
      donde = "inscritos en #{lista.general? ? anio.numero : lista.titulo}"
      mostrados = lista.estudiantes.size
      texto = if lista.cumplen.zero?
                "Nadie cumple los criterios entre los #{miles(lista.inscritos)} #{donde}."
              elsif mostrados == lista.cumplen
                "#{mostrados == 1 ? 'Cumple' : 'Cumplen'} los criterios #{mostrados} de los " \
                  "#{miles(lista.inscritos)} #{donde}."
              else
                "Los #{mostrados} mejores de #{miles(lista.cumplen)} que cumplen los criterios, entre " \
                  "#{miles(lista.inscritos)} #{donde}."
              end
      texto += " Empatan en el #{TOP}º puesto." if mostrados > TOP
      if lista.esperando.positive?
        texto += " Otros #{lista.esperando} tienen notas de #{anio.numero} sin cargar: aparecen cuando se carguen."
      end
      texto
    end

    private

    def lista(clave, titulo, del_grupo)
      cumplen = del_grupo.select(&:cumple?)
      Lista.new(clave, titulo, primeros(cumplen), cumplen.size, del_grupo.size, del_grupo.count(&:esperando_notas?))
    end

    # Los empatados comparten puesto (1, 1, 3…), y cada lista lleva los suyos: el mismo estudiante puede ser 5º
    # en la General y 1º en su año.
    def primeros(cumplen)
      con_puesto = []
      cumplen.sort_by { |c| merito(c).map(&:-@) + [c.nombre] }.each_with_index do |c, i|
        anterior = con_puesto.last
        puesto = anterior && merito(anterior) == merito(c) ? anterior.puesto : i + 1
        break if puesto > TOP

        con_puesto << c.dup.tap { |copia| copia.puesto = puesto }
      end
      con_puesto
    end

    # A dos decimales, como se ven.
    def merito(candidato)
      [candidato.promedio_simple.round(2), candidato.promedio.to_d.round(2)]
    end

    def miles(numero)
      ActiveSupport::NumberHelper.number_to_delimited(numero, delimiter: '.')
    end

    def candidatos
      return [] unless anio

      @candidatos ||= PremioMerito.consultar(CANDIDATOS_SQL, escuela: school.id, anio: anio.numero).map do |fila|
        Candidato.new(
          grade_id: fila['grade_id'], student_id: fila['student_id'], ci: fila['ci'],
          nombre: "#{fila['last_name']}, #{fila['first_name']}", anio_de_carrera: fila['anio_de_carrera'].to_i,
          anual: booleano(fila['anual']), primera_carrera: booleano(fila['primera_carrera']),
          pendientes: fila['pendientes'].to_i, cursadas: fila['cursadas'].to_i, reprobadas: fila['reprobadas'].to_i,
          retiros: fila['retiros'].to_i, equivalencias: fila['equivalencias'].to_i,
          promedio_simple: fila['promedio_simple']&.to_d, promedio: fila['promedio']&.to_d
        )
      end
    end

    def booleano(valor)
      ActiveModel::Type::Boolean.new.cast(valor)
    end

    # El año de la carrera es el ordinal donde inscribió más créditos en el período, sin contar retiros ni
    # optativas (ordinal 0). Quien no tiene créditos ese año no lo cursó: no entra. La carrera va hasta el período.
    CANDIDATOS_SQL = <<~SQL.freeze
      WITH ventana AS (
        SELECT ap.id, ap.modality
        FROM academic_processes ap
        JOIN periods p ON p.id = ap.period_id
        JOIN period_types pt ON pt.id = p.period_type_id
        WHERE ap.school_id = :escuela AND p.year = :anio
          AND ap.modality IN (:modalidades) AND pt.code IN (:periodos_regulares)
      ), del_periodo AS (
        SELECT eap.grade_id, v.modality, ar.status, s.ordinal, s.unit_credits AS creditos
        FROM ventana v
        JOIN enroll_academic_processes eap ON eap.academic_process_id = v.id
        JOIN academic_records ar ON ar.enroll_academic_process_id = eap.id
        JOIN sections sec ON sec.id = ar.section_id
        JOIN courses c ON c.id = sec.course_id
        JOIN subjects s ON s.id = c.subject_id
      ), anio_de_carrera AS (
        SELECT DISTINCT ON (grade_id) grade_id, ordinal
        FROM (
          SELECT grade_id, ordinal, SUM(creditos) AS creditos
          FROM del_periodo
          WHERE status <> :retirado AND ordinal > 0
          GROUP BY grade_id, ordinal
        ) por_ordinal
        WHERE creditos > 0
        ORDER BY grade_id, creditos DESC, ordinal DESC
      ), periodo AS (
        SELECT grade_id, bool_or(modality = :anual) AS anual,
               COUNT(*) FILTER (WHERE status = :sin_calificar) AS pendientes
        FROM del_periodo
        GROUP BY grade_id
      ), de_la_carrera AS (
        SELECT eap.grade_id, ar.status, sec.modality AS seccion, s.unit_credits AS creditos, q.value AS nota,
               ar.status IN (:cursadas) AND s.qualification_type = :numerica
                 AND sec.modality NOT IN (:equivalencias) AND q.value IS NOT NULL AS promedia
        FROM academic_records ar
        JOIN enroll_academic_processes eap ON eap.id = ar.enroll_academic_process_id
        JOIN academic_processes ap ON ap.id = eap.academic_process_id
        JOIN periods p ON p.id = ap.period_id
        JOIN sections sec ON sec.id = ar.section_id
        JOIN courses c ON c.id = sec.course_id
        JOIN subjects s ON s.id = c.subject_id
        LEFT JOIN LATERAL (
          SELECT value FROM qualifications
          WHERE academic_record_id = ar.id AND definitive
          ORDER BY id DESC LIMIT 1
        ) q ON true
        WHERE eap.grade_id IN (SELECT grade_id FROM anio_de_carrera) AND p.year <= :anio
      ), carrera AS (
        SELECT grade_id,
               COUNT(*) FILTER (WHERE status IN (:cursadas)) AS cursadas,
               COUNT(*) FILTER (WHERE status IN (:reprobadas)) AS reprobadas,
               COUNT(*) FILTER (WHERE status = :retirado) AS retiros,
               COUNT(*) FILTER (WHERE seccion IN (:equivalencias)) AS equivalencias,
               AVG(nota) FILTER (WHERE promedia) AS promedio_simple,
               SUM(creditos * nota) FILTER (WHERE promedia)::numeric
                 / NULLIF(SUM(creditos) FILTER (WHERE promedia), 0) AS promedio
        FROM de_la_carrera
        GROUP BY grade_id
      )
      SELECT g.id AS grade_id, g.student_id, u.ci, u.last_name, u.first_name, a.ordinal AS anio_de_carrera,
             pe.anual, pe.pendientes, COALESCE(adm.first_career, false) AS primera_carrera,
             COALESCE(ca.cursadas, 0) AS cursadas, COALESCE(ca.reprobadas, 0) AS reprobadas,
             COALESCE(ca.retiros, 0) AS retiros, COALESCE(ca.equivalencias, 0) AS equivalencias,
             ca.promedio_simple, ca.promedio
      FROM anio_de_carrera a
      JOIN grades g ON g.id = a.grade_id
      JOIN users u ON u.id = g.student_id
      JOIN periodo pe ON pe.grade_id = a.grade_id
      LEFT JOIN admission_types adm ON adm.id = g.admission_type_id
      LEFT JOIN carrera ca ON ca.grade_id = a.grade_id
    SQL
  end
end
