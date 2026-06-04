# Portar Proceso Graduación desde FAU a FHE

> **Origen:** `/Volumes/Personal Info/Documentos/Desarrollo/COES/FAU/coesfau` (rama `main`, commit `d4a4fb3` o superior).
> **Destino:** este repo (FHE, COES-BASE).
> **Última actualización del plan:** 2026-05-29.

> ## ⚠️ CORRECCIÓN 2026-06-04 (lo realmente implementado)
>
> La auditoría original (abajo) describía un flujo **equivocado**, copiado mentalmente de FAU.
> Se verificó contra la app **COES v1 legacy** (`/Volumes/.../FHE/COESFHE/coesapp`, módulo `/grados`)
> y contra capturas de producción provistas por el cliente. El flujo REAL de FHE es:
>
> **`Tesista → Posible Graduando → Graduando → Graduado`** (tesista es el PRIMER paso, no intermedio).
>
> Diferencias clave con lo que decía el plan viejo:
> - **`tesista` va PRIMERO**, antes de `posible_graduando` (el enum ya lo refleja: tesista=1 < posible=2).
> - **`tesista` NO es un `graduate_status` almacenado**: es **derivado** — un `Grade` cursante (o
>   el valor legacy `:tesista`) con una asignatura de **tesis** (`SubjectType.code = 'P'`) inscrita en
>   un `AcademicProcess` activo, no retirada. Ver `Grade.tesistas` y `AcademicRecord.tesis_en_proceso_activo`.
> - **NO hay motor automático de elegibilidad por créditos** (se descartó `eligibility_breakdown`,
>   `evaluate_graduation_eligibility!`, `in_seguimiento`, tab "Seguimiento"). La promoción es manual
>   (Control de Estudios decide), un flip de `graduate_status` con transición validada.
> - La **calificación de la tesis** pertenece al flujo académico normal; el módulo NO la toca
>   (esto evita el choque con el validador `validates_presence_of :qualifications`).
> - Sync graduado↔egresado: promover a `graduado` setea `current_permanence_status = :egresado`;
>   revertir desde `graduado` restaura `:regular` (decisión de negocio explícita).
>
> **Implementación viva** (rama `feature/proceso-graduacion`, sin migraciones):
> - `app/models/grade.rb`: `TransicionGraduacionInvalida`, `GRADUATE_STATUS_TRANSITIONS`,
>   `REVERSE_GRADUATE_TRANSITIONS`, `TAB_NEXT_PROMOTION`, `THESIS_SUBJECT_TYPE_CODE`,
>   scopes `of_schools` y `tesistas`, métodos `promover_graduacion!`, `revertir_graduacion!`,
>   `tesis_activa`, y `after_commit` que invalida el badge del sidebar.
> - `app/models/academic_record.rb`: scope `tesis_en_proceso_activo`.
> - `lib/rails_admin/config/actions/graduacion.rb`: action con 4 tabs homogéneos (todos `Grade`),
>   búsqueda, sort server-side, paginación, descarga xlsx, scoping por `current_user.admin.schools_auh`.
> - Vistas `graduacion.html.haml` + `_recaudos_modal_body.html.haml` (sin sección de créditos/subáreas).
> - Stimulus `recaudos` + `sortable-table` (NO se copió `lazy_eap`, no se usa).
> - Cableado: `ability.rb` (`:graduacion`), `rails_admin.rb` (require+register), `rails_admin.js`
>   (`import "./controllers"`), `controllers/index.js`, `application_helper.rb`
>   (`main_navigation_with_extras`, `SIDEBAR_EXTRA_LINKS`, `sortable_column_link`),
>   `_sidebar_navigation.html.haml`, `application_controller.rb` (rescue CanCan), locale `graduacion`.
> - Tests: `test/models/grade_graduacion_test.rb` (19 casos, verdes).
> - **Follow-ups opcionales (con backup de prod):** (a) backfill legacy `graduate_status='tesista'(1) → 'cursante'(0)`
>   — el módulo ya es tolerante a ese valor, así que NO es bloqueante; (b) `null: false, default: 0`
>   en `grades.graduate_status`.
>
> Lo que sigue debajo es la auditoría ORIGINAL (histórica). **Los snippets de modelo de §1–§5
> describen el flujo viejo y NO se portaron tal cual** — usar como contexto, no como fuente.

## Resumen ejecutivo (HISTÓRICO — flujo desactualizado, ver corrección arriba)

Portar a FHE el módulo "Proceso Graduación" de FAU. **No es cherry-pick directo** — el modelo de datos académico difiere y FHE además debe incorporar `:tesista` como paso intermedio del flujo de graduación.

Flujo en FHE:
`:no_graduable → :posible_graduando → :tesista → :graduando → :graduado`

(En FAU es `:no_graduable → :posible_graduando → :graduando → :graduado` — sin tesis.)

Sin criterio de subáreas: se hace después. Solo elegibilidad por créditos por tipo de asignatura.

---

## 0 · Prerequisitos en FHE (ya verificados)

| Prereq | Estado | Notas |
|---|---|---|
| Ruby 3.1.2 / Rails 7 | ✅ | igual que FAU |
| PaperTrail | ✅ | activo |
| CanCanCan + PARE/Authorizable | ✅ | `app/models/ability.rb`, `authorizable.rb`, `authorized.rb` |
| RailsAdmin custom action infra | ✅ | `lib/rails_admin/config/actions/` ya existe con varias actions |
| `EnhancedController` para RailsAdmin | ✅ | `config.parent_controller = 'EnhancedController'` |
| `Grade.graduate_status` enum | ✅ con divergencia | `{cursante: 0, tesista: 1, posible_graduando: 2, graduando: 3, graduado: 4, postgrado: 5}` — mantener TODOS los valores; el módulo solo manipula `:posible_graduando → :tesista → :graduando → :graduado` |
| `Subject.subject_type_id` FK | ✅ | usar este, NO `modality` (no existe en FHE) |
| `SubjectType` con scope `:obligatoria` | ✅ | `SubjectType.where("lower(name) = 'obligatoria'").first` |
| `RequirementByLevel` con `required_subjects` por nivel/tipo/plan | ✅ | fuente de "créditos requeridos por tipo" en FHE |
| Stimulus controllers infra | ⚠️ parcial | hay `hello_controller`, hay que sumar 3 más |
| `import "./controllers"` en `rails_admin.js` pack | ❌ falta | hay que agregarlo (sin esto los controllers no cargan en /admin) |

---

## 1 · Diferencias clave FAU → FHE

| Concepto | FAU | FHE | Acción al portar |
|---|---|---|---|
| Clasificación de subject | `Subject.modality` enum (`:obligatoria/:optativa/:electiva`) | `Subject.subject_type_id` FK a `SubjectType` | Reescribir `Grade#credits_completed_by_type` para join con `subject_types` |
| Créditos requeridos por tipo | `SubjectType.required_credits` columna directa | Suma de `RequirementByLevel.required_subjects` por study_plan + subject_type (sumado sobre todos los niveles) × `Subject#unit_credits` promedio O usar suma directa de `required_subjects × unit_credits` por nivel | Ver fórmula adaptada abajo |
| `:tesista` en enum | eliminado | mantenido — es paso real | Incluir en transitions |
| Sub-áreas con `min_credits` | sí | no | Saltar el check (devolver `true`) |
| Tabla `areas` | tiene `sub_areas` association | tiene `parent_area_id` (legacy) | No tocar; el check se omite |

### Cálculo adaptado de créditos requeridos por tipo en FHE

FAU hace:
```ruby
SubjectType.find_by("LOWER(name) = ?", 'obligatoria').required_credits  # → integer
```

FHE no tiene `required_credits` en SubjectType. Equivalente: sumar el producto `required_subjects × unit_credits_promedio_del_tipo` sobre todos los niveles del plan.

```ruby
def required_credits_for_type_in_plan(plan, subject_type_name)
  st = SubjectType.find_by("LOWER(name) = ?", subject_type_name.downcase)
  return 0 unless st
  # Total de "materias requeridas" del tipo en todos los niveles del plan
  required_subjects = plan.requirement_by_levels.of_subject_type(st.id).sum(:required_subjects)
  # Créditos promedio de las asignaturas del tipo en este plan (asumiendo unit_credits homogéneo por tipo)
  avg_credits = Subject.where(subject_type_id: st.id).average(:unit_credits).to_f
  (required_subjects * avg_credits).round
end
```

**Alternativa más robusta:** agregar columna `required_credits:integer` a `subject_types` en FHE y poblar con un seed. Reduce divergencia con FAU y la fórmula queda igual. Decidir con CE de Humanidades.

---

## 2 · Archivos a copiar tal cual desde FAU

Las rutas son relativas al root de cada repo (`/Volumes/.../FAU/coesfau` y este repo).

```
app/javascript/controllers/recaudos_controller.js          → copiar igual
app/javascript/controllers/sortable_table_controller.js    → copiar igual
app/javascript/controllers/lazy_eap_controller.js          → copiar igual
app/views/rails_admin/main/graduacion.html.haml            → copiar; ver §4
app/views/rails_admin/main/_recaudos_modal_body.html.haml  → copiar; ver §4
lib/rails_admin/config/actions/graduacion.rb               → copiar; ajustar SORT_COLUMNS si los joins difieren (validar)
```

Comando sugerido (desde root de FHE):

```bash
FAU="/Volumes/Personal Info/Documentos/Desarrollo/COES/FAU/coesfau"
cp "$FAU/app/javascript/controllers/recaudos_controller.js"      app/javascript/controllers/
cp "$FAU/app/javascript/controllers/sortable_table_controller.js" app/javascript/controllers/
cp "$FAU/app/javascript/controllers/lazy_eap_controller.js"      app/javascript/controllers/
cp "$FAU/app/views/rails_admin/main/graduacion.html.haml"        app/views/rails_admin/main/
cp "$FAU/app/views/rails_admin/main/_recaudos_modal_body.html.haml" app/views/rails_admin/main/
cp "$FAU/lib/rails_admin/config/actions/graduacion.rb"           lib/rails_admin/config/actions/
```

---

## 3 · Diffs / agregados a archivos existentes en FHE

### 3.1 · `app/models/grade.rb`

Insertar después del bloque de enums (alrededor de la línea 92):

```ruby
  # === GRADUATION ELIGIBILITY ===

  TERMINAL_PERMANENCE_STATUSES = %w[egresado egresado_doble_titulo desertor retiro_definitivo articulo6 articulo7].freeze
  REQUIRED_SUBJECT_TYPES_NAMES = %w[obligatoria optativa electiva].freeze

  # Transiciones forward del proceso. Otros estados del enum (:cursante, :postgrado)
  # no participan del proceso de graduación.
  GRADUATE_STATUS_TRANSITIONS = {
    posible_graduando: [:no_graduable],
    tesista:           [:posible_graduando],
    graduando:         [:tesista, :posible_graduando],  # permite saltar tesis si CE lo decide
    graduado:          [:graduando]
  }.freeze

  REVERSE_GRADUATE_TRANSITIONS = {
    'graduado'  => 'graduando',
    'graduando' => 'tesista',
    'tesista'   => 'posible_graduando'
  }.freeze

  TAB_NEXT_PROMOTION = {
    'posibles'   => 'tesista',
    'tesistas'   => 'graduando',
    'graduandos' => 'graduado'
  }.freeze

  def terminal_permanence?
    TERMINAL_PERMANENCE_STATUSES.include?(current_permanence_status.to_s)
  end

  def promote_graduate_status!(new_status)
    new_status = new_status.to_sym
    valid_from = GRADUATE_STATUS_TRANSITIONS[new_status]
    raise ArgumentError, "Estado destino inválido: #{new_status.inspect}" unless valid_from
    raise ArgumentError, "Transición no permitida: #{graduate_status} → #{new_status}" unless valid_from.map(&:to_s).include?(graduate_status)

    updates = { graduate_status: new_status }
    if new_status == :graduado && !%w[egresado egresado_doble_titulo].include?(current_permanence_status.to_s)
      updates[:current_permanence_status] = :egresado
    end
    update!(updates)
  end

  def revert_graduate_status!
    target = REVERSE_GRADUATE_TRANSITIONS[graduate_status]
    raise ArgumentError, "No se puede devolver desde #{graduate_status.inspect}" unless target

    updates = { graduate_status: target }
    if graduate_status == 'graduado' && %w[egresado egresado_doble_titulo].include?(current_permanence_status.to_s)
      updates[:current_permanence_status] = :regular
    end
    update!(updates)
  end

  # Breakdown por tipo + flag de cumplimiento (sin subáreas; FHE las añade después)
  def eligibility_breakdown
    @eligibility_breakdown ||= begin
      creditos = REQUIRED_SUBJECT_TYPES_NAMES.each_with_object({}) do |tipo_name, acc|
        required = required_credits_for_type(tipo_name)
        approved = credits_completed_by_type(tipo_name)
        acc[tipo_name.to_sym] = { aprobados: approved, requeridos: required, cumple: approved >= required && required > 0 }
      end
      { creditos: creditos, subareas: [] }  # subáreas vacío: la vista ya maneja .any?
    end
  end

  def eligibility_checks
    b = eligibility_breakdown
    {
      obligatorias: b[:creditos][:obligatoria][:cumple],
      optativas:    b[:creditos][:optativa][:cumple],
      electivas:    b[:creditos][:electiva][:cumple],
      subareas:     true  # se omite en FHE
    }
  end

  def posible_graduando_now?
    !terminal_permanence? && eligibility_checks.values.all?
  end

  def evaluate_graduation_eligibility!
    return if %w[posible_graduando tesista graduando graduado].include?(graduate_status)
    update_column(:graduate_status, Grade.graduate_statuses[:posible_graduando]) if posible_graduando_now?
  end

  # Suma de créditos requeridos para un tipo en el plan del Grade.
  # En FHE: required_subjects × unit_credits promedio por tipo.
  def required_credits_for_type(tipo_name)
    st = SubjectType.find_by("LOWER(name) = ?", tipo_name.downcase)
    return 0 unless st
    required_subjects = study_plan.requirement_by_levels.of_subject_type(st.id).sum(:required_subjects)
    avg = Subject.where(subject_type_id: st.id).average(:unit_credits).to_f
    (required_subjects * avg).round
  end

  # Set "en seguimiento": grades NO terminales y que cumplen ≥3 categorías
  # (sin subáreas → el check de subareas siempre es true, así que basta ≥2 de cr.).
  # En FHE simplificamos: grades NO terminales con ≥1 categoría de créditos cumplida.
  scope :in_seguimiento, lambda {
    where.not(current_permanence_status: TERMINAL_PERMANENCE_STATUSES)
      .where(graduate_status: :no_graduable)
      # Sin pre-cálculo SQL, el filtrado fino se hace in-memory en el controller.
      # Para volumen grande, optimizar después.
  }

  after_commit -> { Rails.cache.delete('sidebar/posible_graduando_count') },
               if: -> { saved_change_to_graduate_status? || destroyed? }
```

> **Nota:** `credits_completed_by_type(tipo)` ya existe en FHE (línea 734 según audit). No duplicar — solo agregar lo nuevo.

### 3.2 · `app/models/ability.rb`

En la rama de `jefe_control_estudio`:

```ruby
can :manage, :graduacion
```

En el loop por `Authorized`:

```ruby
if authd.authorizable.klazz.eql?('Grade') and authd.can_read?
  can :read, :graduacion
  can :manage, :graduacion if authd.can_update?
end
```

### 3.3 · `app/helpers/application_helper.rb`

Si **no existe** `main_navigation_with_extras` (verificar), copiar desde FAU `app/helpers/application_helper.rb` líneas 1-56 y el helper `sortable_column_link`. Adaptar la lambda `visible_if` si el sidebar requiere otro tipo de permission check.

```ruby
SIDEBAR_EXTRA_LINKS = {
  'Reportes' => [
    {
      label: 'Proceso Graduación',
      url:   '/admin/graduacion',
      icon:  'fa-solid fa-user-graduate',
      badge_count: -> { Rails.cache.fetch('sidebar/posible_graduando_count', expires_in: 5.minutes) { Grade.where(graduate_status: [:posible_graduando, :tesista]).count } },
      visible_if:  ->(user) { user&.admin && Ability.new(user).can?(:read, :graduacion) }
    }
  ]
}.freeze

# + def main_navigation_with_extras (copiar de FAU)
# + def sortable_column_link        (copiar de FAU)
```

> **Importante:** RailsAdmin renderiza el sidebar vía `main_navigation`. Hay que verificar si FHE ya override-ó ese helper o si toca hacerlo. Si no, el módulo se accede directo por URL `/admin/graduacion` pero no aparecerá link.

### 3.4 · `config/initializers/rails_admin.rb`

Agregar require + register de la action:

```ruby
require_relative '../../lib/rails_admin/config/actions/graduacion'

# … dentro de config.actions do
graduacion do
  i18n_key :graduacion
end
```

### 3.5 · `app/javascript/rails_admin.js` (CRÍTICO)

Actualmente FHE solo importa `rails_admin/src/rails_admin/base` y custom UI. Agregar:

```js
import "./controllers";
```

Sin esto, Stimulus controllers no cargan en /admin y el modal de recaudos no funciona.

### 3.6 · `app/javascript/controllers/index.js`

Registrar los 3 nuevos controllers:

```js
import RecaudosController from "./recaudos_controller"
application.register("recaudos", RecaudosController)

import LazyEapController from "./lazy_eap_controller"
application.register("lazy-eap", LazyEapController)

import SortableTableController from "./sortable_table_controller"
application.register("sortable-table", SortableTableController)
```

### 3.7 · `app/controllers/application_controller.rb` (recomendado)

Agregar el rescue para CanCan::AccessDenied (ya está en FAU):

```ruby
rescue_from CanCan::AccessDenied do |exception|
  flash[:warning] = "No tiene permiso para acceder a esa sección. Si cree que es un error, contacte al administrador."
  redirect_back_or_to(main_app.root_path)
end
```

Si FHE tiene `EnhancedController`, replicar también ahí.

---

## 4 · Adaptaciones específicas en archivos copiados

### `lib/rails_admin/config/actions/graduacion.rb`

Cambiar la lista de tabs para incluir `'tesistas'`:

```ruby
@tab = %w[seguimiento posibles tesistas graduandos graduados].include?(params[:tab]) ? params[:tab] : 'posibles'
```

Y agregar el case branch:

```ruby
scoped = case @tab
when 'seguimiento' then base.where(id: seguimiento_ids)
when 'posibles'    then base.where(graduate_status: :posible_graduando)
when 'tesistas'    then base.where(graduate_status: :tesista)
when 'graduandos'  then base.where(graduate_status: :graduando)
when 'graduados'   then base.where(graduate_status: :graduado)
end
```

Counts:
```ruby
@counts = {
  seguimiento: seguimiento_ids.size,
  posibles:    by_status_counts['posible_graduando'].to_i,
  tesistas:    by_status_counts['tesista'].to_i,
  graduandos:  by_status_counts['graduando'].to_i,
  graduados:   by_status_counts['graduado'].to_i
}
```

### `app/views/rails_admin/main/graduacion.html.haml`

Agregar la pestaña Tesistas (entre Posibles y Graduandos):

```haml
%li.nav-item
  = link_to url_for(action: :graduacion, controller: 'rails_admin/main', tab: 'tesistas'), class: "nav-link #{'active' if @tab == 'tesistas'}" do
    Tesistas
    - if @counts[:tesistas] > 0
      %span.badge.bg-info.text-dark.ms-1= @counts[:tesistas]
```

El resto de la vista funciona tal cual porque depende de `Grade::TAB_NEXT_PROMOTION` que ya define el flow.

---

## 5 · Migraciones

### 5.1 · Limpiar enum de `graduate_status`

En FAU se hizo `20260521042212_clean_graduate_status_on_grades.rb` que eliminaba `:tesista`. **En FHE NO se hace** — mantenemos todos los valores.

Solo asegurarse de que tenga `null: false` y `default: 0`:

```ruby
class EnsureGraduateStatusOnGrades < ActiveRecord::Migration[7.0]
  def change
    change_column_default :grades, :graduate_status, 0
    change_column_null    :grades, :graduate_status, false, 0
  end
end
```

### 5.2 · Backfill desde `current_permanence_status`

```ruby
class BackfillGraduateStatusFromPermanence < ActiveRecord::Migration[7.0]
  def up
    # Grade con permanence terminal egresado → graduate_status = :graduado (4)
    execute <<~SQL
      UPDATE grades SET graduate_status = 4
      WHERE current_permanence_status IN (8, 9)  -- 8 egresado, 9 egresado_doble_titulo
        AND graduate_status NOT IN (1, 2, 3, 4)  -- no sobreescribir tesista/posible/graduando/graduado
    SQL
  end

  def down
    # no-op
  end
end
```

> **Verificar índices `current_permanence_status` en FHE** — los enteros deben coincidir con el array PERMANENCE_STATUSES. Hacer `Grade.current_permanence_statuses` en consola antes de correr.

---

## 6 · Checklist de aplicación (orden estricto)

- [ ] **Backup BD producción FHE** (cuidado con el backfill).
- [ ] Branch nueva: `git checkout -b feature/proceso-graduacion`
- [ ] Copiar archivos del §2.
- [ ] Aplicar diffs del §3 (en este orden: model → ability → helpers → initializer → JS packs → controllers).
- [ ] Adaptar archivos copiados según §4.
- [ ] Crear migraciones del §5.
- [ ] `bin/rails db:migrate` en dev.
- [ ] `yarn build` para regenerar bundles (rebuild necesario por nuevos Stimulus imports).
- [ ] Reiniciar servidor (`lib/` no autoload).
- [ ] Smoke test (§7).
- [ ] Commit + push a su rama de feature.
- [ ] Merge a `main` cuando CE valide.
- [ ] Deploy: push a dokku.

---

## 7 · Smoke test

1. Login como admin con `jefe_control_estudio`.
2. Visitar `/admin/graduacion`.
3. Verificar las 5 pestañas: Seguimiento · Posibles · Tesistas · Graduandos · Graduados.
4. Buscar por cédula.
5. Abrir modal "Revisar" en un Posible Graduando — ver créditos por tipo, sin sección de subáreas.
6. Promover Posible → Tesista. Verificar flash y que aparece en pestaña Tesistas.
7. Promover Tesista → Graduando. Verificar.
8. Promover Graduando → Graduado. Verificar que `current_permanence_status` quedó `:egresado` (mensaje en flash).
9. Devolver Graduado → Graduando. Verificar restauración de permanencia a `:regular`.
10. Descargar Excel de cada pestaña.
11. Descargar Excel de asignaturas dentro del modal.
12. Sidebar muestra "Proceso Graduación" bajo "Reportes" con badge.
13. Login como admin sin permiso → `/admin/graduacion` → flash de acceso denegado, no error.

---

## 8 · Puntos abiertos / decisiones para CE de Humanidades

- ¿Agregar columna `required_credits` a `subject_types` y poblarla con seed? Simplifica código, alinea con FAU.
- ¿El paso `:tesista` requiere capturar fecha de inicio de tesis? Si sí, agregar columna nullable `thesis_started_at` después.
- ¿Cuándo se considera un :tesista listo para `:graduando`? Hoy es manual (CE lo decide). Documentar criterio.
- ¿Mantener `:cursante` y `:postgrado` como estados paralelos sin participar del proceso? Sí (es la asunción actual; el módulo los ignora).

---

## 9 · Referencias

- Commit base en FAU: `d4a4fb3` "Reversión, sync graduado/egresado y pulido visual"
- Memoria del proyecto FAU: [[graduation-eligibility]] [[stimulus-lazy-load]] [[cancancan-cascade]]
- Plan original (no aplica directo a FHE, pero contexto histórico): `/Users/danielmoros/.claude/plans/hazme-una-revisi-n-exhaustiva-async-mountain.md`
