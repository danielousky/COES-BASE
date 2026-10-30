class School
  # El Excel del Premio al Mérito: una hoja por plan, con el encabezado de la pantalla y la tabla con cebras.
  # Son decenas de filas, así que se arma entero en memoria con caxlsx (la que maneja estilos), sin streaming.
  # FHE es la matriz: se prueba aquí y después se copia igual a COES ODON y FAU.
  class PremioMeritoExcel
    TIPO = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'.freeze
    AZUL = '1F3864'.freeze
    CEBRA = 'EEF3FA'.freeze
    BORDE = 'D9E1F2'.freeze
    MEDALLAS = %w[🥇 🥈 🥉].freeze
    FILA_ENCABEZADO = 7 # las seis de arriba son título, escuela y plan, criterios, embudo, estado y una vacía

    def initialize(premio)
      @premio = premio
      @paquete = Axlsx::Package.new
      @estilos = {}
    end

    def nombre
      "premio_merito_#{@premio.school.code}_#{anio}.xlsx".downcase
    end

    def contenido
      libro = @paquete.workbook
      if @premio.grupos.empty?
        libro.add_worksheet(name: 'Premio') do |hoja|
          encabezado(hoja, nil, "No hay estudiantes de primera carrera con #{anio} evaluado.", 4)
        end
      else
        @premio.grupos.each { |grupo| hoja_del_plan(libro, grupo) }
      end
      @paquete.to_stream.read
    end

    private

    def anio
      @premio.anio&.numero
    end

    def hoja_del_plan(libro, grupo)
      columnas = ['Puesto', 'Cédula', 'Apellidos y nombres', "Créditos #{anio}"]
      columnas << "Eficiencia hasta #{anio}" if grupo.falta
      columnas += ['Promedio simple', 'Promedio ponderado']
      ultima = Axlsx.col_ref(columnas.size - 1)

      libro.add_worksheet(name: grupo.plan.code.to_s.delete('[]:*?/\\')[0, 31]) do |hoja|
        encabezado(hoja, grupo, estado(grupo), columnas.size)
        hoja.add_row columnas, style: estilo(:encabezado), height: 32
        grupo.estudiantes.each_with_index { |candidato, i| fila(hoja, grupo, candidato, i.odd?) }

        hoja.auto_filter = "A#{FILA_ENCABEZADO}:#{ultima}#{FILA_ENCABEZADO + grupo.estudiantes.size}"
        hoja.sheet_view.pane do |pane|
          pane.state = :frozen
          pane.y_split = FILA_ENCABEZADO
          pane.top_left_cell = "A#{FILA_ENCABEZADO + 1}"
          pane.active_pane = :bottom_left
        end
        hoja.page_setup.set(orientation: :landscape)
        hoja.page_setup.fit_to(width: 1, height: 0)

        hoja.add_row []
        hoja.add_row ["Generado en COES el #{I18n.l(Time.current, format: '%d/%m/%Y a las %H:%M')}"], style: estilo(:nota)
        hoja.merge_cells("A#{hoja.rows.size}:#{ultima}#{hoja.rows.size}")
        # Al final: caxlsx recalcula el ancho de una columna con cada fila que se agrega.
        hoja.column_widths(*[8, 13, 42, 14, (16 if grupo.falta), 15, 17].compact)
      end
    end

    def encabezado(hoja, grupo, estado, columnas)
      ultima = Axlsx.col_ref(columnas - 1)
      plan = grupo ? " · #{grupo.plan.name} (#{grupo.plan.code})" : ''
      [
        ["Premio al Mérito Académico #{anio}", :titulo, 24],
        ["#{@premio.school.name}#{plan}", :subtitulo, 18],
        [@premio.texto_criterios, :nota, 30],
        [@premio.embudo.map { |etiqueta, cantidad| "#{miles(cantidad)} #{etiqueta}" }.join('  ▸  '), :nota, 18],
        [estado, grupo.nil? || grupo.falta ? :sin_premio : :con_premio, 30]
      ].each_with_index do |(texto, tipo, alto), i|
        hoja.add_row [texto], style: estilo(tipo), height: alto
        hoja.merge_cells("A#{i + 1}:#{ultima}#{i + 1}")
      end
      hoja.add_row []
    end

    def miles(numero)
      ActiveSupport::NumberHelper.number_to_delimited(numero, delimiter: '.')
    end

    def estado(grupo)
      return @premio.aviso_sin_premio(grupo) if grupo.falta

      cantidad = grupo.estudiantes.size
      "#{cantidad} #{cantidad == 1 ? 'cumple' : 'cumplen'} los criterios. Medalla para los tres primeros puestos."
    end

    def fila(hoja, grupo, candidato, par)
      medalla = MEDALLAS[candidato.puesto - 1] unless grupo.falta
      creditos = candidato.anual ? candidato.creditos.compact.sum : candidato.creditos_texto
      valores = [medalla || candidato.puesto, candidato.ci.to_s, candidato.nombre, creditos]
      tipos = %i[centro centro texto centro]
      if grupo.falta
        valores << candidato.eficiencia.round(2)
        tipos << :numero
      end
      valores += [candidato.promedio_simple&.to_f&.round(2), candidato.promedio&.to_f&.round(2)]
      tipos += %i[numero numero]
      hoja.add_row valores, style: tipos.map { |tipo| estilo(tipo, par: par, destacado: medalla.present?) },
                            types: [nil, :string, :string] + [nil] * (valores.size - 3)
    end

    def estilo(tipo, par: false, destacado: false)
      @estilos[[tipo, par, destacado]] ||= @paquete.workbook.styles.add_style(opciones(tipo, par, destacado))
    end

    def opciones(tipo, par, destacado)
      celda = { bg_color: par ? CEBRA : 'FFFFFF', b: destacado, border: { style: :thin, color: BORDE },
                alignment: { vertical: :center } }
      case tipo
      when :titulo then { b: true, sz: 15, fg_color: AZUL, alignment: { vertical: :center } }
      when :subtitulo then { b: true, sz: 11, alignment: { vertical: :center } }
      when :nota then { sz: 9, i: true, fg_color: '595959', alignment: { wrap_text: true, vertical: :center } }
      when :con_premio then { b: true, fg_color: '1E7B34', alignment: { vertical: :center } }
      when :sin_premio then { b: true, fg_color: 'B45309', alignment: { wrap_text: true, vertical: :center } }
      when :encabezado
        { b: true, fg_color: 'FFFFFF', bg_color: AZUL, border: { style: :thin, color: AZUL },
          alignment: { horizontal: :center, vertical: :center, wrap_text: true } }
      when :texto then celda
      when :centro then celda.merge(alignment: { horizontal: :center, vertical: :center })
      when :numero then celda.merge(format_code: '0.00', alignment: { horizontal: :right, vertical: :center })
      end
    end
  end
end
