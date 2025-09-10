# Sistema de Bitácoras Personalizado - COES-BASE

## Descripción

Se ha implementado un sistema de bitácoras personalizado que mejora significativamente la visualización y gestión de las actividades de los usuarios en el sistema COES-BASE. Este sistema está basado en PaperTrail pero con una interfaz completamente customizada para Rails Admin.

## Características Principales

### 1. Eventos Específicos para Estudiantes
- ✅ Registro de Usuario
- ✅ Registro como Estudiante
- ✅ Inicio de Sesión
- ✅ Cierre de Sesión
- ✅ Actualización de Datos Personales
- ✅ Registro de Grado/Expediente
- ✅ Preinscripción en Período
- ✅ Inscripción en Asignatura
- ✅ Confirmación de Inscripción
- ✅ Retiro de Materia
- ✅ Cambio de Sección
- ✅ Descarga de Documentos
- ✅ Generación de Documentos

### 2. Eventos Específicos para Administradores
- ✅ Registro de Usuario
- ✅ Registro como Administrador
- ✅ Inicio de Sesión
- ✅ Cierre de Sesión
- ✅ Actualización de Datos Personales
- ✅ Preinscripción de Estudiante
- ✅ Aprobación de Inscripción
- ✅ Rechazo de Inscripción
- ✅ Gestión de Expedientes
- ✅ Gestión de Períodos Académicos
- ✅ Gestión de Secciones
- ✅ Gestión de Calificaciones
- ✅ Generación de Documentos
- ✅ Generación de Reportes

## Archivos Creados/Modificados

### 1. Configuración de Rails Admin
- `app/rails_admin/config/initializer.rb` - Configuración personalizada para PaperTrail::Version
- `config/initializers/rails_admin.rb` - Enlaces de navegación a bitácoras

### 2. Modelos y Concerns
- `app/models/concerns/audit_trail_enhancement.rb` - Concern para mejorar la funcionalidad de auditoría
- `app/models/user.rb` - Métodos para tracking de eventos de autenticación
- `app/models/student.rb` - Métodos específicos para eventos de estudiantes

### 3. Controlador y Vistas
- `app/controllers/audit_trails_controller.rb` - Controlador personalizado para bitácoras
- `app/views/audit_trails/index.html.haml` - Vista principal de bitácoras
- `app/views/audit_trails/show.html.haml` - Vista detallada de bitácora
- `app/views/audit_trails/dashboard.html.haml` - Dashboard de estadísticas

### 4. Helpers y Estilos
- `app/helpers/audit_trail_helper.rb` - Helpers para formateo y visualización
- `app/assets/stylesheets/audit_trails.scss` - Estilos personalizados
- `app/javascript/audit_trails.js` - JavaScript para interactividad

### 5. Rutas
- `config/routes.rb` - Rutas para el controlador de bitácoras

## Cómo Usar

### 1. Acceso a las Bitácoras

#### Desde Rails Admin:
- Navegar a la sección "Bitácoras" en el menú lateral
- Seleccionar "Dashboard de Bitácoras" para ver estadísticas
- Seleccionar "Ver Todas las Bitácoras" para la lista completa

#### URLs Directas:
- Dashboard: `/audit_trails/dashboard`
- Lista completa: `/audit_trails`
- Detalle de bitácora: `/audit_trails/:id`

### 2. Funcionalidades Disponibles

#### Dashboard de Bitácoras:
- Estadísticas generales (eventos totales, registros, etc.)
- Actividades recientes
- Usuarios más activos
- Actividad por tipo de registro
- Gráficos de estadísticas

#### Lista de Bitácoras:
- Filtros por tipo de evento, tipo de registro, fechas
- Búsqueda en tiempo real
- Exportación a CSV y Excel
- Paginación
- Vista detallada de cada evento

#### Vista Detallada:
- Información completa del evento
- Usuario responsable con foto de perfil
- Cambios realizados con formato legible
- Estado anterior del registro

### 3. Filtros Disponibles

- **Tipo de Evento**: Creación, Actualización, Eliminación
- **Tipo de Registro**: Usuario, Estudiante, Administrador, etc.
- **Rango de Fechas**: Desde y hasta fechas específicas
- **Usuario**: Filtrar por usuario específico

### 4. Exportación

- **CSV**: Para análisis en hojas de cálculo
- **Excel**: Para reportes más elaborados
- Los filtros aplicados se mantienen en la exportación

## Implementación de Eventos Personalizados

### Para Estudiantes:

```ruby
# En el controlador o modelo
student = Student.find(params[:id])

# Registrar eventos específicos
student.track_grade_registration(grade)
student.track_preenrollment(academic_process)
student.track_subject_enrollment(academic_record)
student.track_enrollment_confirmation(enroll_academic_process)
student.track_subject_withdrawal(academic_record, "Razón del retiro")
student.track_section_change(old_section, new_section)
student.track_document_download("constancia", "Constancia de Estudios")
student.track_document_generation("kardex", "Kardex Académico")
student.track_personal_data_update(["first_name", "last_name"])
```

### Para Usuarios (Autenticación):

```ruby
# En el controlador de sesiones
user = User.find(params[:id])

# Registrar eventos de autenticación
user.track_login_event(request.remote_ip, request.user_agent)
user.track_logout_event(request.remote_ip, request.user_agent)
user.track_student_registration
user.track_admin_registration
```

## Personalización

### Agregar Nuevos Tipos de Eventos:

1. Editar `app/models/concerns/audit_trail_enhancement.rb`
2. Agregar el nuevo evento a `STUDENT_EVENTS` o `ADMIN_EVENTS`
3. Crear método de tracking en el modelo correspondiente

### Modificar la Visualización:

1. Editar `app/views/audit_trails/` para cambiar las vistas
2. Modificar `app/helpers/audit_trail_helper.rb` para cambiar el formateo
3. Actualizar `app/assets/stylesheets/audit_trails.scss` para cambiar estilos

### Agregar Nuevos Filtros:

1. Modificar `app/controllers/audit_trails_controller.rb`
2. Actualizar la vista `index.html.haml` con el nuevo filtro
3. Agregar lógica de filtrado en el controlador

## Beneficios

1. **Mejor Visualización**: Interfaz moderna y fácil de usar
2. **Filtros Avanzados**: Búsqueda y filtrado eficiente
3. **Estadísticas**: Dashboard con métricas importantes
4. **Exportación**: Reportes en múltiples formatos
5. **Eventos Específicos**: Tracking detallado de actividades académicas
6. **Responsive**: Funciona en dispositivos móviles
7. **Accesible**: Navegación desde Rails Admin

## Consideraciones Técnicas

- Utiliza PaperTrail para el almacenamiento de versiones
- Compatible con la configuración existente de Rails Admin
- No afecta el rendimiento del sistema principal
- Mantiene la integridad de los datos existentes
- Fácil de mantener y extender

## Próximos Pasos

1. **Integración con Controladores**: Implementar los métodos de tracking en los controladores existentes
2. **Notificaciones**: Agregar notificaciones para eventos importantes
3. **Reportes Automáticos**: Generar reportes periódicos
4. **API**: Crear endpoints para integración con otros sistemas
5. **Backup**: Implementar respaldo automático de bitácoras

## Soporte

Para cualquier duda o problema con el sistema de bitácoras, revisar:
1. Los logs de Rails para errores
2. La configuración de PaperTrail
3. Los permisos de usuario en Rails Admin
4. La conectividad de la base de datos

El sistema está diseñado para ser robusto y fácil de usar, proporcionando una experiencia superior para la gestión de bitácoras en COES-BASE.

