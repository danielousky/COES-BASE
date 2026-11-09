class School
  # El Excel del premio por la carrera: una hoja por lista (General, 1º año…), con los estilos, la cabecera y el
  # cierre del Excel por año. FHE es la matriz: se prueba aquí y después se copia igual a COES ODON y FAU.
  class PremioMeritoCarreraExcel < PremioMeritoExcel
    FILA_ENCABEZADO = 6 # las cinco de arriba son título, escuela y lista, criterios, resumen y una vacía

    def contenido
      @premio.listas.each { |lista| hoja_de_la_lista(@paquete.workbook, lista) }
      @paquete.to_stream.read
    end

    private

    def hoja_de_la_lista(libro, lista)
      columnas = ['Puesto', 'Cédula', 'Apellidos y nombres', *(@premio.unidad.capitalize if lista.general?),
                  "Eficiencia\nhasta #{anio}", "Promedio simple\nde la carrera\nhasta #{anio}",
                  "Promedio ponderado\nde la carrera\nhasta #{anio}"]
      ultima = Axlsx.col_ref(columnas.size - 1)

      libro.add_worksheet(name: lista.titulo) do |hoja|
        cabecera(hoja, ultima, [
                   ["Premio al Mérito Académico #{anio}", :titulo, 24],
                   ["#{@premio.school.name} · #{lista.titulo}", :subtitulo, 18],
                   [@premio.texto_criterios, :nota, 30],
                   [@premio.resumen(lista), lista.estudiantes.any? ? :con_premio : :sin_premio, 30]
                 ])
        hoja.add_row columnas, style: estilo(:encabezado), height: 58
        lista.estudiantes.each_with_index { |candidato, i| fila_de_la_lista(hoja, lista, candidato, i.odd?) }
        cerrar(hoja, ultima, lista.estudiantes.size)
        # Al final: caxlsx recalcula el ancho de una columna con cada fila que se agrega.
        hoja.column_widths(8, 13, 42, *(8 if lista.general?), 12, 14, 14)
      end
    end

    def fila_de_la_lista(hoja, lista, candidato, par)
      medalla = MEDALLAS[candidato.puesto - 1]
      valores = [medalla || candidato.puesto, candidato.ci.to_s, candidato.nombre,
                 *("#{candidato.anio_de_carrera}º" if lista.general?),
                 candidato.eficiencia.round(2), candidato.promedio_simple&.to_f&.round(2),
                 candidato.promedio&.to_f&.round(2)]
      tipos = %i[centro centro texto] + (lista.general? ? %i[centro] : []) + %i[numero numero numero]
      hoja.add_row valores, style: tipos.map { |tipo| estilo(tipo, par: par, destacado: medalla.present?) },
                            types: [nil, :string, :string] + [nil] * (valores.size - 3)
    end
  end
end
