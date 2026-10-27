# Seguridad: `before_action` con predicados que no detienen nada

Detectado el 2026-10-19 trabajando el candado de prelaciones (rama `prelaciones-fase-1-candado`).
Rama de este trabajo: `seguridad-before-action-admin` (sale de `main`, c360f69).

## El problema

```ruby
before_action :logged_as_admin?
```

`logged_as_admin?` (`app/controllers/application_controller.rb`) **devuelve** true/false, pero un `before_action`
sólo corta la petición si hace `redirect_to`/`render`. El valor de retorno se ignora. Resultado: el filtro
no protege nada y la acción corre para **cualquier usuario autenticado** (`authenticate_user!` sí está en
ApplicationController), incluido un estudiante. Lo mismo con `logged_as_teacher_or_admin?`.

Ya está corregido en `SubjectLinksController` (rama de prelaciones, con pruebas en
`test/integration/mapa_prelaciones_test.rb`, "un estudiante no puede crear ni borrar prelaciones"). Sigue igual en
los demás.

## Dónde está (leído en el código; **falta reproducirlo con pruebas**)

| Controlador | Línea | Qué expone | Gravedad |
|---|---|---|---|
| `authorizeds_controller.rb` | 2 | `update_authorize`: reescribe los permisos (read/create/update/delete/import/export) de **cualquier** admin por `params[:id]` | **Crítica**: escalada de privilegios |
| `qualifications_controller.rb` | 3 | `update` de calificaciones de **cualquier** `AcademicRecord` por id | **Crítica**: cambiar notas |
| `partial_qualifications_controller.rb` | 3 | `update` de notas parciales de cualquier `AcademicRecord` | **Crítica** |
| `schools_controller.rb` | 4 | `update` de escuela, `export_grades`, `export_grades_stream` (datos de estudiantes) | Alta |
| `export_controller.rb` | 2 | `history_grade`, `xls`, `general`: exportes con datos personales/académicos | Alta |
| `enrollment_days_controller.rb` | 2 | crear/borrar citas horarias (`create`, `destroy`, `destroy_all`), `send_email_enrollment_day`, `export` | Alta |
| `session_admin_controller.rb` | 4 | `change_period_session` | Media |
| `subjects_controller.rb` | 2 | `show` | Baja |

Ojo también: aunque el rol sea correcto, varias acciones no revisan **sobre qué** se actúa:
- un profesor (`logged_as_teacher?`) podría calificar secciones que no son suyas;
- un admin de una escuela podría tocar registros de otra (`current_admin.schools_auh`);
- `authorizeds#update_authorize` debería exigir permiso de gestión sobre `Admin`, no sólo ser admin.

## Cómo corregirlo (propuesta)

1. En `ApplicationController`, filtros que **sí** cortan, sin tocar los predicados (se usan en vistas):
   ```ruby
   def authenticate_admin!
     return if logged_as_admin?
     respond_to do |format|
       format.html { redirect_back fallback_location: root_path, alert: 'No autorizado' }
       format.any { head :forbidden }
     end
   end
   # ídem authenticate_teacher_or_admin!
   ```
   Revisar antes si ya existe algo parecido (`authenticate_student!`, `authenticate_teacher!` sí existen: ver cómo cortan).
2. Cambiar cada `before_action :logged_as_...?` por el filtro nuevo.
3. Donde aplique, autorización por objeto: profesor dueño de la sección; admin con la escuela en `schools_auh`;
   permiso `authorized_to(...)` sobre la clase.
4. Barrido final: `grep -rn "before_action" app/controllers` y revisar **todos** los controladores fuera de
   RailsAdmin que no tengan protección real (no sólo los de la tabla).

## Pruebas (antes de corregir: que fallen; después: que pasen)

- Por cada controlador de la tabla: un estudiante autenticado recibe 403/redirect y **el dato no cambia**.
- Profesor ajeno a la sección no puede calificar; el profesor dueño sí.
- Admin de otra escuela no puede.
- El flujo normal del admin y del profesor sigue funcionando (no regresiones).
- Login en pruebas de integración: `post user_session_path, params: {user: {ci:, password: 'password123'}}`
  (así `after_sign_in_path_for` fija `session[:rol]`).
- La otra sesión (prelaciones) usa `coesbase_test`. Para no pisarse corriendo pruebas a la vez, usar otra base:
  `DATABASE_URL=postgres://localhost/coesbase_test_seguridad bin/rails db:test:prepare` y correr las pruebas
  con esa misma variable.

## Reglas

- Push a `origin` y despliegue: **sólo con autorización explícita de Daniel**.
- Antes de desplegar, revisar en producción (sólo lectura, `PaperTrail::Version`) si hay rastro de uso indebido:
  cambios en `Authorized`, calificaciones con `whodunnit` de usuarios que no son admin ni profesor.
- No matar servidores Rails de otras sesiones (la de prelaciones usa el puerto 3001).

## Estado (2026-10-26, rama `seguridad-before-action-admin`, sobre `main` 2afb174)

Ya resuelto en `main` por otra sesión: `subject_links` (filtro real + escuela), `export#xls` (403 si no es admin),
`users#reset_password` (exige gestionar el rol más alto).

Resuelto en esta rama (`test/integration/seguridad_before_action_test.rb`, 21 casos: 15 fallaban sin el arreglo):

- `require_admin` ahora corta con `rechazar`: HTML vuelve atrás con aviso; JSON/JS/descargas reciben 403.
  `administra_escuela?(school_id)` para la autorización por objeto.
- `authorizeds#update_authorize`: admin **y** `authorized_update?('Admin')`.
- `qualifications` / `partial_qualifications` (`AutorizaCalificacion`): profesor titular de la sección mientras no esté
  cerrada (`qualified`), o admin con `authorized_manage?('Section')` sobre la escuela de la sección (mismo criterio con
  que RailsAdmin muestra la planilla).
- `schools` (update y exportes), `export#history_grade` y `#xls`, `enrollment_days` (create/destroy/export): admin de
  esa escuela. `enrollment_days#destroy_all` (borra las de todas las escuelas, sin uso en vistas): sólo desarrollador.
- `session_admin`, `subjects`: `require_admin`.

## Pendiente: barrido (paso 4) — controladores ruteados sin ningún filtro de rol

Medido el 2026-10-26 con una sonda como **estudiante** autenticado (no queda en la suite):

| Petición | Respuesta | Efecto |
|---|---|---|
| `DELETE /period_types/:id` | 302 | el tipo de período **se borra** |
| `PATCH /academic_processes/:id` `max_credits=99` | 302 | **se guarda** |
| `DELETE /enroll_academic_processes/:id` | 302 | la inscripción **se borra** |
| `PATCH /academic_records/:id` `status=aprobado` | 302 | no cambió, pero sólo por validación del modelo |
| `PATCH /sections/:id` `teacher_id` | 302 | no cambió sólo porque la sección no estaba `totaly_qualified?` |

Sin filtro (scaffolds `resources` completos): `faculties` (+ `schools/admission_types/study_plans/areas/subjects`
anidados), `periods`, `period_types`, `profiles`, `banks`, `study_plans` (salvo `oferta_estudiante`), `courses`,
`academic_processes` (salvo 4 acciones), `grades` (incluye `kardex`, `import_inscripciones`), `academic_records`
(salvo `destroy`), `sections` (`create`, `update`, `change_qualification_status`, `export`, `index`),
`enroll_academic_processes` (`update`, `destroy`, `create`, `show`…), `payment_reports` (`show`, `edit`, `create`),
`timetables#show`, `students#update`.

Ojo al corregir: varios los usan estudiantes y profesores (`enroll`, `reserve_space`, `study_constance`, reporte de
pago, `sections#show/update` para cerrar el acta, `kardex`, `students#update`, horarios). No es un `require_admin`
global: hay que decidir acción por acción quién la usa, con prueba de cada flujo legítimo.
