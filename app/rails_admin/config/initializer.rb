# Configuración personalizada para Rails Admin
# Customización de la visualización de bitácoras

RailsAdmin.config do |config|
  # Configuración del modelo PaperTrail::Version para mejor visualización
  config.model 'PaperTrail::Version' do
    # Configuración de la vista de lista
    list do
      # Campos visibles en la lista
      field :created_at do
        label "Fecha y Hora"
        formatted_value do
          value.strftime("%d/%m/%Y %H:%M:%S") if value
        end
      end
      
      field :event do
        label "Acción"
        formatted_value do
          case value
          when 'create'
            '<span class="badge badge-success">Registro</span>'
          when 'update'
            '<span class="badge badge-warning">Actualización</span>'
          when 'destroy'
            '<span class="badge badge-danger">Eliminación</span>'
          else
            '<span class="badge badge-info">' + value.to_s.humanize + '</span>'
          end.html_safe
        end
      end
      
      field :item_type do
        label "Tipo de Registro"
        formatted_value do
          case value
          when 'User'
            '<i class="fa fa-user"></i> Usuario'
          when 'Student'
            '<i class="fa fa-graduation-cap"></i> Estudiante'
          when 'Admin'
            '<i class="fa fa-user-shield"></i> Administrador'
          when 'Teacher'
            '<i class="fa fa-chalkboard-teacher"></i> Docente'
          when 'Grade'
            '<i class="fa fa-id-card"></i> Expediente'
          when 'EnrollAcademicProcess'
            '<i class="fa fa-clipboard-list"></i> Proceso Académico'
          when 'AcademicRecord'
            '<i class="fa fa-book"></i> Registro Académico'
          when 'Section'
            '<i class="fa fa-users"></i> Sección'
          when 'Subject'
            '<i class="fa fa-book-open"></i> Asignatura'
          when 'AcademicProcess'
            '<i class="fa fa-calendar-alt"></i> Período Académico'
          when 'PaymentReport'
            '<i class="fa fa-file-invoice-dollar"></i> Reporte de Pago'
          else
            '<i class="fa fa-file"></i> ' + value.to_s.humanize
          end.html_safe
        end
      end
      
      field :whodunnit do
        label "Usuario"
        formatted_value do
          if value.present?
            user = User.find_by(id: value)
            if user
              "#{user.first_name} #{user.last_name} (#{user.ci})"
            else
              "Usuario ID: #{value}"
            end
          else
            "Sistema"
          end
        end
      end
      
      field :object_changes do
        label "Detalles del Cambio"
        formatted_value do
          if value.present?
            begin
              changes = JSON.parse(value)
              if changes.is_a?(Hash)
                changes_list = changes.map do |key, change|
                  if change.is_a?(Array) && change.length == 2
                    old_val = change[0].nil? ? "vacío" : change[0].to_s.truncate(30)
                    new_val = change[1].nil? ? "vacío" : change[1].to_s.truncate(30)
                    "<strong>#{key.humanize}:</strong> #{old_val} → #{new_val}"
                  else
                    "<strong>#{key.humanize}:</strong> #{change.to_s.truncate(50)}"
                  end
                end.join("<br>")
                changes_list.html_safe
              else
                value.to_s.truncate(100)
              end
            rescue JSON::ParserError
              value.to_s.truncate(100)
            end
          else
            "Sin cambios detallados"
          end
        end
      end
    end
    
    # Configuración de la vista de detalle
    show do
      field :created_at do
        label "Fecha y Hora"
        formatted_value do
          value.strftime("%d/%m/%Y %H:%M:%S") if value
        end
      end
      
      field :event do
        label "Tipo de Acción"
        formatted_value do
          case value
          when 'create'
            '<span class="badge badge-success badge-lg">Registro Creado</span>'
          when 'update'
            '<span class="badge badge-warning badge-lg">Registro Actualizado</span>'
          when 'destroy'
            '<span class="badge badge-danger badge-lg">Registro Eliminado</span>'
          else
            '<span class="badge badge-info badge-lg">' + value.to_s.humanize + '</span>'
          end.html_safe
        end
      end
      
      field :item_type do
        label "Tipo de Registro"
      end
      
      field :item_id do
        label "ID del Registro"
      end
      
      field :whodunnit do
        label "Usuario Responsable"
        formatted_value do
          if value.present?
            user = User.find_by(id: value)
            if user
              "<strong>#{user.first_name} #{user.last_name}</strong><br>
               <small class='text-muted'>CI: #{user.ci} | Email: #{user.email}</small>".html_safe
            else
              "Usuario ID: #{value}"
            end
          else
            "Sistema Automático"
          end
        end
      end
      
      field :object do
        label "Estado Anterior"
        formatted_value do
          if value.present?
            begin
              obj = JSON.parse(value)
              "<pre class='bg-light p-3 rounded'>#{JSON.pretty_generate(obj)}</pre>".html_safe
            rescue JSON::ParserError
              value.to_s
            end
          else
            "Sin estado anterior"
          end
        end
      end
      
      field :object_changes do
        label "Cambios Realizados"
        formatted_value do
          if value.present?
            begin
              changes = JSON.parse(value)
              if changes.is_a?(Hash) && changes.any?
                changes_html = changes.map do |key, change|
                  if change.is_a?(Array) && change.length == 2
                    old_val = change[0].nil? ? "<em>vacío</em>" : change[0].to_s
                    new_val = change[1].nil? ? "<em>vacío</em>" : change[1].to_s
                    "<div class='change-item mb-2 p-2 border rounded'>
                       <strong class='text-primary'>#{key.humanize}</strong><br>
                       <span class='text-danger'>Antes:</span> #{old_val}<br>
                       <span class='text-success'>Después:</span> #{new_val}
                     </div>"
                  else
                    "<div class='change-item mb-2 p-2 border rounded'>
                       <strong class='text-primary'>#{key.humanize}</strong><br>
                       <span class='text-info'>Valor:</span> #{change.to_s}
                     </div>"
                  end
                end.join("")
                changes_html.html_safe
              else
                "<pre class='bg-light p-3 rounded'>#{JSON.pretty_generate(changes)}</pre>".html_safe
              end
            rescue JSON::ParserError
              "<pre class='bg-light p-3 rounded'>#{value}</pre>".html_safe
            end
          else
            "Sin cambios registrados"
          end
        end
      end
    end
    
    # Configuración de búsqueda
    configure :created_at, :datetime do
      filterable true
    end
    
    configure :event, :string do
      filterable true
    end
    
    configure :item_type, :string do
      filterable true
    end
    
    configure :whodunnit, :string do
      filterable true
    end
  end
end

