# Feature: Limpiar Citas Horarias (vencidas / todas)

Funcionalidad para limpiar citas horarias de una escuela, con opción de limpiar
solo las vencidas (anteriores a hoy) o todas. Incluye split button dropdown en la UI.

---

## Archivos a modificar (4)

### 1. `app/models/enrollment_day.rb`

Agregar scope `expired`:

```ruby
scope :expired, -> { where('start < ?', Time.current.beginning_of_day) }
```

---

### 2. `config/routes.rb`

Agregar dentro del bloque `resources :academic_processes` → `member do`:

```ruby
delete 'clean_appointments'
```

---

### 3. `app/controllers/academic_processes_controller.rb`

Agregar `clean_appointments` a los `before_action`:

```ruby
before_action :set_academic_process, only: %i[ ... clean_appointments ... ]
before_action :require_admin, only: %i[ ... clean_appointments ... ]
```

Agregar el action:

```ruby
def clean_appointments
  school = @academic_process.school
  expired_only = params[:scope] == 'expired'

  if expired_only
    today = Time.current.beginning_of_day
    total_days = school.enrollment_days.expired.delete_all
    total_grades = school.grades.with_appointment_time.where('appointment_time < ?', today).update_all(appointment_time: nil, duration_slot_time: nil)
    scope_label = 'vencidas'
  else
    total_days = school.enrollment_days.delete_all
    total_grades = school.grades.with_appointment_time.update_all(appointment_time: nil, duration_slot_time: nil)
    scope_label = 'todas'
  end

  if total_days == 0 && total_grades == 0
    flash[:info] = "No se encontraron citas #{scope_label} para limpiar"
  else
    flash[:success] = "Citas #{scope_label} limpiadas: #{total_days} #{'jornada'.pluralize(total_days)} eliminada(s), #{total_grades} #{'cita'.pluralize(total_grades)} de estudiantes limpiada(s)"
  end
  redirect_back fallback_location: "/admin/academic_process/#{@academic_process.id}/enrollment_day"
end
```

---

### 4. `app/views/rails_admin/main/enrollment_day.html.haml`

Reemplazar el botón antiguo de "Limpiar Citas" por el split button dropdown.
La vista completa queda así:

```haml
%h4.bg-primary.text-light.text-center= "Cita Horaria #{@object.short_desc}"
- if (current_user&.admin&.authorized_read? 'AcademicProcess')
  - if @object.process_before
    - clean_url = "/academic_processes/#{@object.id}/clean_appointments"
    - expired_count = @object.school.enrollment_days.expired.count
    - expired_confirm = "Esta acción eliminará #{expired_count} jornada(s) vencida(s) (anteriores a hoy) y limpiará las citas asignadas de esos días en #{@object.school.name}. ¿Está seguro?"
    - all_confirm = "ATENCIÓN: Esta acción eliminará TODAS las jornadas de cita horaria (incluyendo futuras) y limpiará TODAS las citas asignadas a los estudiantes de #{@object.school.name}. ¿Está completamente seguro?"
    .d-flex.justify-content-end.mb-3
      .btn-group
        = link_to "#{clean_url}?scope=expired", method: :delete, class: 'btn btn-outline-warning', 'data-bs-toggle': :tooltip, title: 'Eliminar solo las jornadas con fecha anterior a hoy', data: {confirm: expired_confirm} do
          %i.fa-solid.fa-broom
          Limpiar Vencidas
          - if expired_count > 0
            %span.badge.bg-warning.text-dark.ms-1= expired_count
        %button.btn.btn-outline-warning.dropdown-toggle.dropdown-toggle-split{"data-bs-toggle": :dropdown, "aria-expanded": false}
          %span.visually-hidden Más opciones
        %ul.dropdown-menu.dropdown-menu-end
          %li
            = link_to clean_url, method: :delete, class: 'dropdown-item text-danger', data: {confirm: all_confirm} do
              %i.fa-solid.fa-triangle-exclamation.me-1
              Limpiar Todas las Citas

    .alert.alert-danger
      %b Atención
      Si está planificando una nueva jornada de inscripción por Cita Horaria, es importante que corra la función 'Actualizar Estados Estudiantes' indicada con el enlace abajo para que COES actualice tanto el estado de permanecia como los valores de eficiencia y promedios de cada estudiante antes de agregar la nueva cita.
      .text-center
        - url = "/academic_processes/#{@object.process_before.id}/run_regulation?id_return=#{@object.id}"
        - title = "Actualiza tanto el estado de permanecia como la eficiencia y los promedios de los estudiantes basado en los períodos anteriores al actual #{@object.process_name}. Incluye eliminación de Citas"
        - confirm_msg = "Esta acción actualizará el estado de permanencia y los promedios de notas de cada estudiante que cursó materias en el periodo anterior #{@object.process_before&.process_name}. También limpiará todas las citas horarias. ¿Está completamente seguro?"
        = link_to url, method: :post, class: 'btn m-3 btn-lg btn-primary', 'data-bs-toggle': :tooltip, title: title, data: {confirm: confirm_msg, 'disable-with': "<i class='fa fa-spinner fa-spin'></i> Procesando, espere...".html_safe } do
          %i.fa-regular.fa-refresh
          Actualizar Estados Estudiantes

    .text-center.alert.alert-warning.p-2.mb-3= "Sólo se permitirá la inscripción a estudiantes: Regulares, Reincorporados, en Artículo 3 o con un Permiso Especial.".html_safe

    = render partial: "/enrollment_days/index", locals: {academic_process: @object}

  - else
    .alert.alert-warning= 'Sin período anterio vinculado. Para habilitar el sistema de Cita Horaria en este período, por favor edítelo y agréguele un período anterior.'
- else
  .text-center.alert.alert-warning Acceso Restringido
```

---

## Requisitos previos

- Modelo `EnrollmentDay` con campos: `start` (datetime), `academic_process_id`
- Modelo `Grade` con campos: `appointment_time` (datetime), `duration_slot_time` (integer)
- Scope `Grade.with_appointment_time` ya existente (`where.not(appointment_time: nil)`)
- Bootstrap 5, FontAwesome, Rails UJS o Turbo
