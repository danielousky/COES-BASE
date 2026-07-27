# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

COES-BASE is a Rails 7 academic management system (Control de Estudios) for Venezuelan higher education. It manages student enrollment, grading, academic records, and institutional workflows. The codebase is entirely in Spanish.

## Tech Stack

- **Ruby 3.1.2** / **Rails 7.0.4+** (gemset: coesbase)
- **PostgreSQL** database
- **HAML** templating (not ERB)
- **Webpack 5** for JavaScript bundling, **Sass** for CSS
- **Bootstrap 5.2**, **jQuery 3.6**, **Stimulus**, **Turbo Rails**
- **Devise** (auth), **CanCanCan** (authorization), **Rails Admin 3.1** (interfaz administrativa principal)
- **Delayed Job** for background processing
- **PaperTrail** for audit trail/versioning
- **Simple Form** with Bootstrap wrappers
- **WickedPdf** + **Prawn** for PDF generation
- Deployed via **Dokku** to dokku@coesfhe.com

## Development Commands

```bash
# Start dev server (runs web, JS watcher, CSS watcher)
foreman start -f Procfile.dev
# Or individually:
bin/rails server -p 3000
yarn build --watch
yarn build:css --watch

# Database
bin/rails db:create db:migrate db:seed

# Tests (Minitest)
bin/rails test                        # all tests
bin/rails test test/models/            # model tests only
bin/rails test test/models/user_test.rb # single file
bin/rails test test/models/user_test.rb:42  # single test by line

# Assets
yarn build              # compile JS via webpack
yarn build:css          # compile SCSS + copy FontAwesome webfonts

# Background worker (Delayed Job)
bundle exec rake jobs:work

# Linting
bundle exec rubocop
bundle exec rubocop -a   # auto-correct

# Console
bin/rails console
```

## Architecture

### Authentication & Authorization
- **Devise** handles authentication with custom password reset flows. **El login es por `ci`** (cédula), no por email — `users.ci` es la columna única
- Three main roles: **Admin**, **Teacher**, **Student** — each with dedicated session controllers and dashboards
- `ApplicationController` provides helpers like `logged_as_admin?`
- **CanCanCan con autorización en dos niveles**, toda en `app/models/ability.rb`:
  1. `Admin#role` (enum `desarrollador: 0, jefe_control_estudio: 1, asistente: 3`) define el permiso base — `desarrollador` obtiene `can :manage, :all`
  2. Para el resto, permisos **granulares por clase** vía `Authorizable` / `Authorized`: cada admin tiene registros `authorizeds` que habilitan read/create/update/delete/import/export sobre una clase concreta (`authorizable.klazz`). `Authorizable::IMPORTABLES` limita qué modelos aceptan importación

### Core Domain Models (~109 archivos en `app/models`)

La cadena central del dominio **no es lineal** — `Grade` es la pieza que conecta al estudiante con todo lo demás:

```
Faculty → School → StudyPlan          Period ─┐
                        │                     ├→ AcademicProcess → Course → Section
Student → Grade ────────┘                     │                              │
            │  (expediente: estudiante + plan + tipo de ingreso)             │
            └→ EnrollAcademicProcess ──→ AcademicRecord ←─────────────────────┘
               (inscripción al lapso)     (inscripción a una sección)
                                                │
                                                └→ Qualification / PartialQualification
```

- **`Grade`** = expediente del estudiante en un plan de estudio. Un mismo `Student` puede tener varios `Grade` (varias carreras/planes). Casi todo cuelga de aquí: `belongs_to :student, primary_key: :user_id`
- **`EnrollAcademicProcess`** = inscripción de un `Grade` en un `AcademicProcess` (lapso). Tiene `enum enroll_status: [:preinscrito, :reservado, :confirmado]` y `enum permanence_status`
- **`AcademicRecord`** = la inscripción concreta en una `Section`; de ahí cuelgan las calificaciones

### ⚠️ Tablas legacy en español conviviendo con las nuevas en inglés

El schema contiene **dos generaciones de tablas**. Los modelos en español (`Asignatura`, `Escuela`, `Estudiante`, `Profesor`, `Periodo`, `Seccion`, `Plan`, `Usuario`, `Catedra`, `Direccion`, `Grado`, `Administrador`, `Reportepago`…) son `ApplicationRecord` reales que mapean las tablas del sistema anterior (`asignaturas`, `escuelas`, `estudiantes`, `secciones`, `planes`, `usuarios`…), y existen para migración/importación de datos históricos.

**El código nuevo va siempre contra los modelos en inglés** (`Subject`, `School`, `Student`, `Teacher`, `Period`, `Section`, `StudyPlan`, `User`). Antes de tocar un modelo con nombre en español, verifica si estás en el lado legacy — es el error más fácil de cometer en este repo.

### Módulos y validators: ojo con la ubicación

- Los **concerns viven sueltos en `app/models/`**, no en `app/models/concerns/` (la única excepción es `Transaccionable`): `Numerizable` (estados de permanencia + cálculo de promedios, eficiencia y créditos), `Totalizable`, `Qualifying`, `Schoolizable`, `AcademicProcessable`, `Userable`
- Los **custom validators también están en `app/models/`**, no en `app/validators/`: `AsignaturaAprobadaUnicaValidator`, `SameSchoolValidator`, `SamePeriodValidator`, `ApprovedAndEnrollingValidator`, `UniqEnrollmentDayValidator`, etc. Codifican las reglas de negocio académicas complejas

### Rails Admin es la interfaz administrativa principal

No es un panel accesorio: la mayor parte de la gestión ocurre ahí (`/admin`).

- Configuración en `config/initializers/rails_admin.rb` (~259 líneas), muy customizada
- **Acciones personalizadas** en `lib/rails_admin/config/actions/`: `graduacion`, `move_academic_records`, `custom_export`, `export`, `dashboard`, `index`
- `MainController` está sobrescrito en `app/controllers/rails_admin/main_controller.rb`
- Importación vía `rails_admin_import`; los modelos importables los define `Authorizable::IMPORTABLES`

### Background Jobs
- **Delayed Job** with ActiveRecord backend (not Sidekiq/Redis)
- Config: 90-min max run time, 3 attempts, 60s sleep delay
- Key jobs: `MassiveActasGenerationJob` (bulk PDF generation), `MassEmailJob`
- Production: `dokku ps:scale coes-base web=1 worker=1`

### Data Import/Export
- **Import**: Excel files via `ImportCsv`, `ImportXslx`, `ExcelConverter`, and `rails_admin_import`
- **Export**: PDF (WickedPdf + Prawn), XLSX (xlsxtream), CSV streaming
- Export controllers: `ExportController`, `ExportCsvController`
- Key reports: Kardex, Constancias, Actas (academic transcripts/records)

### File Storage
- ActiveStorage with AWS S3 support (fallback to local)

## Code Conventions

- **Language**: All code, comments, commit messages, and UI are in **Spanish**
- **Views**: Use HAML, not ERB
- **Forms**: Use Simple Form with Bootstrap wrappers
- **Time**: Use `Time.current` (not `Time.now`) for timezone consistency (configured to "Caracas")
- **Locale**: Default locale is `:es` — i18n files in `config/locales/`
- **Rubocop**: Max line length 120 chars; many style cops disabled (see `.rubocop.yml`)
- **Audit**: Models use PaperTrail for change tracking
- **No editar a mano** las cabeceras `# == Schema Information` de los modelos: las genera la gem `annotate`
- Tras commitear cambios en Ruby/HAML/JS, correr el skill `coes:rails-style`

## Deployment

```bash
# Deploy to production
git push dokku main

# Production processes (Procfile)
web: bundle exec puma -C config/puma.rb
worker: bundle exec rake jobs:work
release: bundle exec rake db:migrate
```

## Key Configuration

- `config/application.rb`: Timezone "Caracas", locale :es, delayed_job queue adapter
- `config/initializers/delayed_job_config.rb`: Job retry/timeout settings
- `config/initializers/devise.rb`: Authentication config
- `config/initializers/wicked_pdf.rb`: PDF generation settings
- Environment variables: `DATABASE_URL`, `WEB_CONCURRENCY`, `PROVIDER_EMAIL_*` (SMTP)
