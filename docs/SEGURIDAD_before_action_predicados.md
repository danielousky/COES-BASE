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

## Barrido (paso 4) — 2026-10-26

Medido primero con una sonda como **estudiante** autenticado: `DELETE /period_types/:id` lo borraba,
`PATCH /academic_processes/:id` guardaba `max_credits=99`, `DELETE /enroll_academic_processes/:id` borraba la inscripción.

Pruebas: `test/integration/seguridad_barrido_test.rb` (21 casos; sin el arreglo fallan 15, las 6 restantes son los
flujos legítimos de estudiante, profesor y admin). Suite completa: 182 runs, 0 failures, 0 errors.

| Controlador | Antes | Ahora |
|---|---|---|
| `faculties`, `periods`, `period_types`, `profiles`, `banks`, `admission_types` (scaffolds sin vistas que los enlacen) | cualquiera | `autorizar_como_en_rails_admin`: los mismos permisos de `Ability` que en RailsAdmin |
| `areas`, `study_plans` | cualquiera | ídem + escuela; `save_requirement_by_level` con el criterio de la vista Estructura (`authorized_manage? 'StudyPlan'`) |
| `academic_processes` | cualquiera (salvo 4 acciones) | admin de la escuela del proceso (y de la de destino / la del proceso a clonar); `download_actas` sólo admin |
| `courses` | cualquiera | admin de la escuela del proceso |
| `grades` | cualquiera; el kardex de **cualquier** expediente | kardex: el estudiante dueño o admin de la escuela con lectura de `Grade` (igual que el botón); lo demás, admin |
| `enroll_academic_processes` | estudiante: confirmarse a sí mismo (`enroll_status`), inscribir/reservar en expediente ajeno o fuera de su cita; borrar inscripciones | `reserve_space`/`enroll`: admin de la escuela, o el estudiante dueño cuando `AccesoInscripcion#habilitado?` (la misma regla de la pantalla) y el proceso es de su escuela; `enroll_status` sólo lo fija el admin; constancia: dueño o admin; resto, admin de la escuela |
| `payment_reports` | crear un reporte ya `Validado` o sobre la inscripción de otro | estudiante sólo sobre lo suyo y sin `status`; validar/borrar, admin de la escuela |
| `sections` | cerrar/reabrir acta, cambiar profesor y capacidad | `update`: admin de la escuela, o el titular con el acta abierta y **sólo** `qualified: true`; reabrir, `create`, `index`, `bulk_delete` (acotado a sus procesos): admin; `show`/`export`: admin de la escuela o profesor de la sección |
| `academic_records` | cambiar el estado de cualquier registro | admin de la escuela; el titular con el acta abierta, sólo `status` (inasistencia y absolutas de la planilla) |
| `students`, `addresses` | ver/editar los de otro estudiante (también por render implícito de `students#edit`) | sólo los propios |
| `timetables` | el horario de cualquiera | el propio (profesor o estudiante) o admin de la escuela |

Detalles:
- `rechazar` responde 403 en JSON con `status: 'error'`; el JS de inscripción ya no pisa el texto de la opción cuando el
  rechazo no trae cupo (p. ej. se venció la cita con el formulario abierto).
- `reserve_space_acid_test` y `academic_records_create_acid_test` entraban con `sign_in` (sin `session[:rol]`) y con
  actores que en la realidad no existen: el estudiante reservaba con la inscripción cerrada y creaba histórico. Ahora el
  estudiante está habilitado (`enroll: true`, `enabled_enroll_process`) y el histórico lo carga un jefe de CE. Lo que
  miden (atomicidad) no cambió.

## Pendiente

- `export_csv` (requiere admin, pero no acota por escuela) e `importer` (cualquier admin importa: no revisa
  `can :import` ni `Authorizable::IMPORTABLES`).
- Historial: `Authorized`, `PartialQualification`, `PeriodType`, `Address` y `EnrollmentDay` ya tienen
  `has_paper_trail` (rama `historial-modelos-sin-paper-trail`). Dos límites: `version_limit = 30` (global) guarda
  sólo las 30 últimas versiones de cada registro, y `academic_processes#clean_appointments` borra citas con
  `delete_all`, que no pasa por PaperTrail.
- Notificar/decidir sobre la descarga masiva de kardex del 2026-10-12 (ver auditoría abajo).
- Servidor (hecho el 2026-10-27, fuera del repo): fail2ban 0.11.2 con `/etc/fail2ban/jail.d/coes.local` y filtros
  `coes-escaneo` (rutas .php/wp-/.env/cgi-bin/.git, 5 en 10 min → 1 día) y `coes-login` (POST sign_in fallido, 100 en
  10 min → 15 min; el máximo legítimo medido desde una NAT móvil fue 38), más `sshd` en modo aggressive. Se ignora
  190.169.0.0/16 (UCV). Se quitaron de `ufw` las reglas 2375/2376 (API de Docker, nada escuchaba) y se detuvo un
  `rails c` huérfano (`coes-base.run.17922`, del 2025-10-02).

## Auditoría de producción (2026-10-26, sólo lectura)

`psql` con `default_transaction_read_only=on` (comprobado: un `CREATE` falla) sobre 2.219.476 versiones
(2024-06-20 → 2026-10-27) y el log de nginx (14 días, desde 2026-10-12). Criterio: acciones de un usuario que no era
admin *en ese momento* (alta/baja según las versiones de `Admin`).

Sin rastro de abuso de escritura:

- Inscripciones pasadas a `confirmado` y pagos `Validado` por no-admins de hoy: todas de 5 usuarios que eran admin
  entonces (dados de baja el 2026-10-21). Ningún ex-admin actuó después de su baja.
- Notas puestas por profesores en secciones ajenas (23 versiones, 10 profesores): en todos los casos el profesor
  calificó su propia sección y días después un admin movió la inscripción (`section_id`) a la actual.
- `User`/`Student` editados por alguien distinto del dueño que no fuera admin: ninguno.
- El único `PaymentReport#destroy` de un estudiante cae en cascada al anular su propia inscripción.
- `update_authorize` (7 llamadas en 14 días): IPs de oficina y casa del jefe de Control de Estudio; los cambios en
  `authorizeds` son de asistentes.

**Sí hubo abuso de lectura (IDOR en `grades#kardex`, cerrado en esta rama):** el 2026-10-12 entre 15:26 y 15:41
(hora de Caracas), desde la IP compartida 179.63.108.1, con la sesión de la cuenta de estudiante `user_id` 15958
(expediente 15129; única sesión iniciada desde esa IP en esa franja) se descargaron 29 kardex ajenos recorriendo ids:
15109, 15110, 15122, 15127, 15130–15140, 15145, 15150, 15160, 15170, 15180, 15190, 15200, 15300, 15350, 15450,
15500, 15000, 15100. No hubo otra ráfaga en el log (el siguiente máximo son 4 ids distintos en 10 min, de una IP
de la UCV). Antes del 2026-10-12 no hay log de nginx para saberlo.
- `subjects#show` en HTML falla para todos (`undefined method modality`); el JSON que usa el histórico va bien.
