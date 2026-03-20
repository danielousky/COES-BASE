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
- **Devise** (auth), **CanCanCan** (authorization), **Rails Admin** (admin panel)
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
- **Devise** handles authentication with custom password reset flows
- **CanCanCan** manages role-based authorization
- Three main roles: **Admin**, **Teacher**, **Student** — each with dedicated session controllers and dashboards
- `ApplicationController` provides helpers like `logged_as_admin?`

### Core Domain Models (~104 models)
- **Academic structure**: Faculty → School → Department → Area → Subject → StudyPlan
- **Process flow**: Period → AcademicProcess → EnrollAcademicProcess → Section → AcademicRecord → Qualification
- **People**: User → Profile, with polymorphic roles (Admin, Teacher, Student)
- **Grading**: Grade, Qualification, PartialQualification with `Numerizable` concern for status logic
- Heavy use of **custom validators** (e.g., `AsignaturaAprobadaUnicaValidator`, `SameSchoolValidator`) for complex academic business rules

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
